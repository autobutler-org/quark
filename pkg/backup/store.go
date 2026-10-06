package backup

import (
	"context"
	"fmt"
	"slices"
)

// The store keeps its own copy of every job and hands out copies. The running
// snapshot mutates its job between Updates while status requests encode what
// Get returns, so a shared pointer is a data race.

func (s *InMemoryBackupJobStore) Create(_ context.Context, job *BackupJob) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, exists := s.jobs[job.ID]; exists {
		return fmt.Errorf("backup job %s already exists", job.ID)
	}
	s.jobs[job.ID] = cloneJob(job)
	return nil
}

func (s *InMemoryBackupJobStore) Get(_ context.Context, jobID string) (*BackupJob, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	job, exists := s.jobs[jobID]
	if !exists {
		return nil, fmt.Errorf("backup job %s not found", jobID)
	}
	return cloneJob(job), nil
}

func (s *InMemoryBackupJobStore) Update(_ context.Context, job *BackupJob) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, exists := s.jobs[job.ID]; !exists {
		return fmt.Errorf("backup job %s not found", job.ID)
	}
	s.jobs[job.ID] = cloneJob(job)
	return nil
}

func (s *InMemoryBackupJobStore) List(_ context.Context) ([]*BackupJob, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	jobs := make([]*BackupJob, 0, len(s.jobs))
	for _, job := range s.jobs {
		jobs = append(jobs, cloneJob(job))
	}
	return jobs, nil
}

func cloneJob(job *BackupJob) *BackupJob {
	clone := *job
	clone.SourceDevices = slices.Clone(job.SourceDevices)
	if job.CompletedAt != nil {
		completedAt := *job.CompletedAt
		clone.CompletedAt = &completedAt
	}
	return &clone
}
