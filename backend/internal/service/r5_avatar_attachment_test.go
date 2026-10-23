package service

import (
	"bytes"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sync/atomic"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/config"
	"github.com/sky/personal-ledger/internal/model"
	"gorm.io/gorm"
)

func r5Services(f *backupIntegrityFixture) *Services {
	return NewServices(f.repos, &config.Config{Storage: config.StorageConfig{
		UploadPath: f.uploadPath, MaxFileSize: 1, AllowedTypes: "png,txt",
	}})
}

func TestR5ExportRejectsInvalidAvatarReferences(t *testing.T) {
	for _, kind := range []string{"profile", "member", "deleted_member"} {
		for _, invalid := range []string{"missing", "foreign", "noncanonical"} {
			t.Run(kind+"/"+invalid, func(t *testing.T) {
				f := attachmentLifecycleFixture(t)
				avatar := fmt.Sprintf("/uploads/%d/avatars/profile/missing.png", f.user.ID)
				switch invalid {
				case "foreign":
					avatar = "/uploads/999/avatars/profile/avatar.png"
					writeIntegrityFixture(t, f.uploadPath, "999/avatars/profile/avatar.png", minimalPNG())
				case "noncanonical":
					avatar = fmt.Sprintf("/uploads/%d/avatars/profile/../profile/avatar.png", f.user.ID)
					writeIntegrityFixture(t, f.uploadPath, f.userDirectory()+"/avatars/profile/avatar.png", minimalPNG())
				}
				if kind == "profile" {
					if err := f.db.Model(f.user).Update("avatar", avatar).Error; err != nil {
						t.Fatal(err)
					}
				} else {
					member := &model.FamilyMember{ID: uuid.NewString(), UserID: f.user.ID, Name: "Historical", Avatar: avatar}
					if err := f.db.Create(member).Error; err != nil {
						t.Fatal(err)
					}
					if kind == "deleted_member" {
						if err := f.db.Delete(member).Error; err != nil {
							t.Fatal(err)
						}
					}
				}
				backup, err := f.service.CreateBackup(f.user.ID)
				if backup != nil || !errors.Is(err, ErrBackupAttachmentIntegrity) {
					t.Fatalf("invalid %s avatar exported: backup=%t err=%v", kind, backup != nil, err)
				}
			})
		}
	}
}

func TestR5AvatarBackupRoundTripAndLegacyNilManifest(t *testing.T) {
	f := attachmentLifecycleFixture(t)
	profilePath := f.userDirectory() + "/avatars/profile/avatar.png"
	memberPath := f.userDirectory() + "/avatars/member/avatar.png"
	for _, path := range []string{profilePath, memberPath} {
		writeIntegrityFixture(t, f.uploadPath, path, minimalPNG())
	}
	if err := f.db.Model(f.user).Update("avatar", "/uploads/"+profilePath).Error; err != nil {
		t.Fatal(err)
	}
	member := &model.FamilyMember{ID: uuid.NewString(), UserID: f.user.ID, Name: "Historical", Avatar: memberPath}
	if err := f.db.Create(member).Error; err != nil {
		t.Fatal(err)
	}
	if err := f.db.Delete(member).Error; err != nil {
		t.Fatal(err)
	}
	backup, err := f.service.CreateBackup(f.user.ID)
	if err != nil {
		t.Fatal(err)
	}
	target := attachmentLifecycleFixture(t)
	user := &model.User{Username: "different-target", PasswordHash: "synthetic"}
	if err := target.repos.User.Create(user); err != nil {
		t.Fatal(err)
	}
	if err := target.service.RestoreBackup(user.ID, writeBackupFile(t, backup)); err != nil {
		t.Fatal(err)
	}
	storedUser, err := target.repos.User.GetByID(user.ID)
	if err != nil {
		t.Fatal(err)
	}
	if storedUser.Avatar != fmt.Sprintf("/uploads/%d/avatars/profile/avatar.png", user.ID) {
		t.Fatalf("profile avatar=%q", storedUser.Avatar)
	}
	var storedMember model.FamilyMember
	if err := target.db.Unscoped().First(&storedMember, "id = ?", member.ID).Error; err != nil {
		t.Fatal(err)
	}
	if !storedMember.DeletedAt.Valid || storedMember.Avatar != fmt.Sprintf("%d/avatars/member/avatar.png", user.ID) {
		t.Fatalf("member not preserved: %#v", storedMember)
	}
	for _, suffix := range []string{"avatars/profile/avatar.png", "avatars/member/avatar.png"} {
		content, err := os.ReadFile(filepath.Join(target.uploadPath, fmt.Sprint(user.ID), suffix))
		if err != nil || !bytes.Equal(content, minimalPNG()) {
			t.Fatalf("restored avatar %s: %v", suffix, err)
		}
	}
	// A nil manifest preserves the existing tree rather than declaring it empty.
	backup.Attachments = nil
	if err := target.service.RestoreBackup(user.ID, writeBackupFile(t, backup)); err != nil {
		t.Fatalf("legacy nil manifest: %v", err)
	}
	if _, err := os.Stat(filepath.Join(target.uploadPath, fmt.Sprint(user.ID), "avatars/profile/avatar.png")); err != nil {
		t.Fatal(err)
	}
}

func r5AvatarWriter(t *testing.T, f *backupIntegrityFixture, kind string) (func(string) error, func() string) {
	t.Helper()
	s := r5Services(f)
	member := &model.FamilyMember{ID: uuid.NewString(), UserID: f.user.ID, Name: "Existing", Avatar: "legacy-icon", IsDefault: true, IsEnabled: true}
	if kind == "member_update" {
		if err := f.repos.FamilyMember.Create(member); err != nil {
			t.Fatal(err)
		}
	}
	write := func(avatar string) error {
		switch kind {
		case "profile":
			_, err := s.Auth.UpdateProfile(f.user.ID, "Display", "display@example.test", avatar, "Bio")
			return err
		case "member_create":
			created, err := s.FamilyMember.Create(f.user.ID, CreateFamilyMemberRequest{Name: "Created", Avatar: avatar})
			if err == nil {
				member = created
			}
			return err
		default:
			_, err := s.FamilyMember.Update(member.ID, f.user.ID, UpdateFamilyMemberRequest{Name: "Updated", Avatar: avatar})
			return err
		}
	}
	read := func() string {
		if kind == "profile" {
			user, err := f.repos.User.GetByID(f.user.ID)
			if err != nil {
				t.Fatal(err)
			}
			return user.Avatar
		}
		var rows []model.FamilyMember
		if err := f.db.Where("user_id = ?", f.user.ID).Find(&rows).Error; err != nil {
			t.Fatal(err)
		}
		if len(rows) == 0 {
			return ""
		}
		if len(rows) != 1 {
			t.Fatalf("unexpected member count=%d", len(rows))
		}
		return rows[0].Avatar
	}
	return write, read
}

func TestR5AvatarSubmissionValidatesInternalFiles(t *testing.T) {
	for _, kind := range []string{"profile", "member_create", "member_update"} {
		for _, input := range []string{"missing", "foreign", "noncanonical", "internal", "external", "empty", "legacy_icon"} {
			t.Run(kind+"/"+input, func(t *testing.T) {
				f := attachmentLifecycleFixture(t)
				write, read := r5AvatarWriter(t, f, kind)
				before := read()
				avatar := fmt.Sprintf("/uploads/%d/avatars/profile/avatar.png", f.user.ID)
				writeIntegrityFixture(t, f.uploadPath, f.userDirectory()+"/avatars/profile/avatar.png", minimalPNG())
				switch input {
				case "missing":
					avatar = fmt.Sprintf("/uploads/%d/avatars/profile/missing.png", f.user.ID)
				case "foreign":
					avatar = "/uploads/999/avatars/profile/avatar.png"
					writeIntegrityFixture(t, f.uploadPath, "999/avatars/profile/avatar.png", minimalPNG())
				case "noncanonical":
					avatar = fmt.Sprintf("/uploads/%d/avatars/profile/../profile/avatar.png", f.user.ID)
				case "external":
					avatar = "https://example.test/avatar.png?size=64"
				case "empty":
					avatar = ""
				case "legacy_icon":
					avatar = "legacy-icon"
				}
				err := write(avatar)
				invalid := input == "missing" || input == "foreign" || input == "noncanonical"
				if invalid {
					if err == nil {
						t.Fatal("invalid internal avatar submission succeeded")
					}
					if got := read(); got != before {
						t.Fatalf("rejected avatar mutated data: before=%q after=%q", before, got)
					}
				} else if err != nil || read() != avatar {
					t.Fatalf("valid avatar changed/rejected: avatar=%q stored=%q err=%v", avatar, read(), err)
				}
			})
		}
	}
}

func TestR5AvatarSubmissionWaitsForGCAndRejectsCollectedFile(t *testing.T) {
	for _, kind := range []string{"profile", "member_create", "member_update"} {
		t.Run(kind, func(t *testing.T) {
			f := attachmentLifecycleFixture(t)
			write, read := r5AvatarWriter(t, f, kind)
			before := read()
			path := f.userDirectory() + "/avatars/profile/old.png"
			writeIntegrityFixture(t, f.uploadPath, path, minimalPNG())
			old := time.Now().Add(-48 * time.Hour)
			if err := os.Chtimes(filepath.Join(f.uploadPath, path), old, old); err != nil {
				t.Fatal(err)
			}
			entered, resume := make(chan struct{}), make(chan struct{})
			var paused atomic.Bool
			name := "r5:pause-gc-after-references"
			if err := f.db.Callback().Query().After("gorm:query").Register(name, func(query *gorm.DB) {
				if query.Statement.Table == "lending_records" && paused.CompareAndSwap(false, true) {
					close(entered)
					<-resume
				}
			}); err != nil {
				t.Fatal(err)
			}
			defer f.db.Callback().Query().Remove(name)
			gcDone := make(chan error, 1)
			go func() {
				_, err := r5Services(f).Upload.CollectOrphanedFiles(f.user.ID, time.Now().Add(-24*time.Hour))
				gcDone <- err
			}()
			<-entered
			writeDone := make(chan error, 1)
			started := make(chan struct{})
			go func() { close(started); writeDone <- write("/uploads/" + path) }()
			<-started
			var early bool
			var writeErr error
			select {
			case writeErr = <-writeDone:
				early = true
			case <-time.After(100 * time.Millisecond):
			}
			close(resume)
			if err := <-gcDone; err != nil {
				t.Fatal(err)
			}
			if !early {
				writeErr = <-writeDone
			}
			if early {
				t.Error("avatar submission crossed GC's attachment write barrier")
			}
			if !errors.Is(writeErr, ErrAttachmentFileUnavailable) || read() != before {
				t.Fatalf("collected avatar was committed: err=%v stored=%q", writeErr, read())
			}
		})
	}
}

func TestR5GCWaitsForAvatarCommit(t *testing.T) {
	for _, kind := range []string{"profile", "member_create", "member_update"} {
		t.Run(kind, func(t *testing.T) {
			f := attachmentLifecycleFixture(t)
			write, read := r5AvatarWriter(t, f, kind)
			path := f.userDirectory() + "/avatars/profile/old.png"
			writeIntegrityFixture(t, f.uploadPath, path, minimalPNG())
			old := time.Now().Add(-48 * time.Hour)
			if err := os.Chtimes(filepath.Join(f.uploadPath, path), old, old); err != nil {
				t.Fatal(err)
			}
			entered, resume := make(chan struct{}), make(chan struct{})
			var paused atomic.Bool
			name := "r5:pause-avatar-before-persistence"
			pause := func(query *gorm.DB) {
				if (query.Statement.Table == "users" || query.Statement.Table == "family_members") && paused.CompareAndSwap(false, true) {
					close(entered)
					<-resume
				}
			}
			if kind == "member_create" {
				if err := f.db.Callback().Create().Before("gorm:create").Register(name, pause); err != nil {
					t.Fatal(err)
				}
				defer f.db.Callback().Create().Remove(name)
			} else {
				if err := f.db.Callback().Update().Before("gorm:update").Register(name, pause); err != nil {
					t.Fatal(err)
				}
				defer f.db.Callback().Update().Remove(name)
			}
			writeDone := make(chan error, 1)
			go func() { writeDone <- write("/uploads/" + path) }()
			<-entered
			gcDone := make(chan error, 1)
			go func() {
				_, err := r5Services(f).Upload.CollectOrphanedFiles(f.user.ID, time.Now().Add(-24*time.Hour))
				gcDone <- err
			}()
			var early bool
			var gcErr error
			select {
			case gcErr = <-gcDone:
				early = true
			case <-time.After(100 * time.Millisecond):
			}
			close(resume)
			if err := <-writeDone; err != nil {
				t.Fatal(err)
			}
			if !early {
				gcErr = <-gcDone
			}
			if early {
				t.Error("GC crossed avatar persistence's attachment read barrier")
			}
			if gcErr != nil || read() != "/uploads/"+path {
				t.Fatalf("avatar commit: gc=%v stored=%q", gcErr, read())
			}
			if _, err := os.Stat(filepath.Join(f.uploadPath, path)); err != nil {
				t.Fatalf("committed avatar was collected: %v", err)
			}
		})
	}
}

func TestR5OtherHistoricalReferencesSurviveGCAndRestore(t *testing.T) {
	for _, kind := range []string{"reminder", "lending", "lending_record", "family_member"} {
		t.Run(kind, func(t *testing.T) {
			f := attachmentLifecycleFixture(t)
			s := r5Services(f)
			id := uuid.NewString()
			suffix := "reminders/" + id + "/receipt.txt"
			var row any
			switch kind {
			case "reminder":
				row = &model.Reminder{ID: id, UserID: f.user.ID, Name: "Historical", PaymentDay: 1, Evidence: fmt.Sprintf(`["%s/%s"]`, f.userDirectory(), suffix)}
			case "lending", "lending_record":
				lending := &model.Lending{ID: uuid.NewString(), UserID: f.user.ID, Type: "lend", ContactName: "Historical", Principal: 1, LendDate: time.Now()}
				if kind == "lending" {
					lending.ID = id
					suffix = "lendings/" + id + "/receipt.txt"
					lending.Evidence = fmt.Sprintf(`["%s/%s"]`, f.userDirectory(), suffix)
					row = lending
				} else {
					if err := f.db.Create(lending).Error; err != nil {
						t.Fatal(err)
					}
					suffix = "lendings/" + lending.ID + "_repay_history/receipt.txt"
					row = &model.LendingRecord{ID: id, LendingID: lending.ID, UserID: f.user.ID, Type: "repay", Amount: 1, RecordDate: time.Now(), Evidence: fmt.Sprintf(`["%s/%s"]`, f.userDirectory(), suffix)}
				}
			case "family_member":
				suffix = "avatars/" + id + "/avatar.png"
				row = &model.FamilyMember{ID: id, UserID: f.user.ID, Name: "Historical", Avatar: "/uploads/" + f.userDirectory() + "/" + suffix}
			}
			if err := f.db.Create(row).Error; err != nil {
				t.Fatal(err)
			}
			if err := f.db.Delete(row).Error; err != nil {
				t.Fatal(err)
			}
			path := f.userDirectory() + "/" + suffix
			writeIntegrityFixture(t, f.uploadPath, path, []byte("historical attachment"))
			orphan := f.userDirectory() + "/avatars/orphan/old.txt"
			writeIntegrityFixture(t, f.uploadPath, orphan, []byte("orphan"))
			old := time.Now().Add(-48 * time.Hour)
			for _, path := range []string{path, orphan} {
				if err := os.Chtimes(filepath.Join(f.uploadPath, path), old, old); err != nil {
					t.Fatal(err)
				}
			}
			if referenced, err := s.Upload.IsReferenced(f.user.ID, path); err != nil || !referenced {
				t.Fatalf("historical reference=%v err=%v", referenced, err)
			}
			if err := s.Upload.Delete(f.user.ID, path); !errors.Is(err, ErrUploadReferenced) {
				t.Fatalf("historical deletion=%v", err)
			}
			removed, err := s.Upload.CollectOrphanedFiles(f.user.ID, time.Now().Add(-24*time.Hour))
			if err != nil || len(removed) != 1 || removed[0] != orphan {
				t.Fatalf("GC removed=%v err=%v", removed, err)
			}
			backup, err := s.Backup.CreateBackup(f.user.ID)
			if err != nil {
				t.Fatal(err)
			}
			target := attachmentLifecycleFixture(t)
			if err := target.service.RestoreBackup(target.user.ID, writeBackupFile(t, backup)); err != nil {
				t.Fatal(err)
			}
			content, err := os.ReadFile(filepath.Join(target.uploadPath, path))
			if err != nil || string(content) != "historical attachment" {
				t.Fatalf("historical attachment lost: %v", err)
			}
			var count int64
			if err := target.db.Unscoped().Model(row).Where("id = ? AND deleted_at IS NOT NULL", id).Count(&count).Error; err != nil || count != 1 {
				t.Fatalf("tombstone lost: count=%d err=%v", count, err)
			}
			if err := os.Remove(filepath.Join(f.uploadPath, path)); err != nil {
				t.Fatal(err)
			}
			if backup, err := s.Backup.CreateBackup(f.user.ID); backup != nil || !errors.Is(err, ErrBackupAttachmentIntegrity) {
				t.Fatalf("missing historical file exported: backup=%t err=%v", backup != nil, err)
			}
		})
	}
}
