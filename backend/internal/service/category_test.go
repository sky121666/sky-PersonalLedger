package service

import (
	"errors"
	"path/filepath"
	"testing"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/database"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
)

func TestSystemCategoryCannotBeUpdatedOrDeleted(t *testing.T) {
	db, err := database.Init(filepath.Join(t.TempDir(), "ledger.db"))
	if err != nil {
		t.Fatalf("init db: %v", err)
	}
	repos := repository.NewRepositories(db)
	user := &model.User{Username: "admin", PasswordHash: "hash"}
	if err := repos.User.Create(user); err != nil {
		t.Fatalf("create user: %v", err)
	}
	category := &model.Category{
		ID: uuid.NewString(), UserID: user.ID, Name: "餐饮", Type: "expense", IsSystem: true,
	}
	if err := repos.Category.Create(category); err != nil {
		t.Fatalf("create category: %v", err)
	}
	svc := NewCategoryService(repos.Category)

	if _, err := svc.Update(category.ID, user.ID, UpdateCategoryRequest{Name: "被篡改"}); !errors.Is(err, ErrSystemCategoryProtected) {
		t.Fatalf("update error = %v, want ErrSystemCategoryProtected", err)
	}
	if err := svc.Delete(category.ID, user.ID); !errors.Is(err, ErrSystemCategoryProtected) {
		t.Fatalf("delete error = %v, want ErrSystemCategoryProtected", err)
	}
	persisted, err := repos.Category.GetByID(category.ID)
	if err != nil {
		t.Fatalf("load protected category: %v", err)
	}
	if persisted.Name != "餐饮" || !persisted.IsSystem {
		t.Fatalf("protected category changed: %#v", persisted)
	}
}

func TestCustomCategoryCanStillBeUpdatedAndDeleted(t *testing.T) {
	db, err := database.Init(filepath.Join(t.TempDir(), "ledger.db"))
	if err != nil {
		t.Fatalf("init db: %v", err)
	}
	repos := repository.NewRepositories(db)
	user := &model.User{Username: "admin", PasswordHash: "hash"}
	if err := repos.User.Create(user); err != nil {
		t.Fatalf("create user: %v", err)
	}
	category := &model.Category{ID: uuid.NewString(), UserID: user.ID, Name: "旧名称", Type: "expense"}
	if err := repos.Category.Create(category); err != nil {
		t.Fatalf("create category: %v", err)
	}
	svc := NewCategoryService(repos.Category)

	updated, err := svc.Update(category.ID, user.ID, UpdateCategoryRequest{Name: "新名称"})
	if err != nil || updated.Name != "新名称" {
		t.Fatalf("updated category = %#v, err = %v", updated, err)
	}
	if err := svc.Delete(category.ID, user.ID); err != nil {
		t.Fatalf("delete custom category: %v", err)
	}
	if _, err := repos.Category.GetByID(category.ID); err == nil {
		t.Fatal("custom category still exists after delete")
	}
}
