package service

import "sync"

// attachmentStorageBarrier prevents a committed restore from swapping a user
// directory while uploads, downloads, metadata persistence, deletion, backup,
// or garbage collection are using the active attachment tree.
var attachmentStorageBarrier sync.RWMutex

var attachmentRecoveryPendingUsers sync.Map

func acquireAttachmentStorageRead() func() {
	attachmentStorageBarrier.RLock()
	return attachmentStorageBarrier.RUnlock
}

// AcquireAttachmentStorageRead lets HTTP file responders keep the barrier for
// the entire send, not merely while resolving a pathname.
func AcquireAttachmentStorageRead() func() {
	return acquireAttachmentStorageRead()
}

func acquireAttachmentStorageWrite() func() {
	attachmentStorageBarrier.Lock()
	return attachmentStorageBarrier.Unlock
}

func markAttachmentRecoveryPending(userID uint) {
	if userID != 0 {
		attachmentRecoveryPendingUsers.Store(userID, struct{}{})
	}
}

func clearAttachmentRecoveryPending(userID uint) {
	attachmentRecoveryPendingUsers.Delete(userID)
}

// AttachmentStorageAvailable is checked by upload handlers after acquiring
// the shared barrier. A user with committed but not-yet-active attachments is
// failed closed until forward recovery succeeds.
func AttachmentStorageAvailable(userID uint) bool {
	_, pending := attachmentRecoveryPendingUsers.Load(userID)
	return !pending
}
