package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"sort"
	"strings"
	"time"

	"github.com/heroiclabs/nakama-common/api"
	"github.com/heroiclabs/nakama-common/runtime"
)

func isLeaderboardNotFoundError(err error) bool {
	if err == nil {
		return false
	}
	return strings.Contains(strings.ToLower(err.Error()), "leaderboard not found")
}

func leaderboardRecordPlayCount(record *api.LeaderboardRecord) int64 {
	if record == nil {
		return 0
	}
	count := int64(record.GetNumScore())
	if count <= 0 {
		// Old records can report zero submissions; treat them as one play.
		return 1
	}
	return count
}

func rpcSubmitScore(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	userID, ok := ctx.Value(runtime.RUNTIME_CTX_USER_ID).(string)
	if !ok || userID == "" {
		return "", runtime.NewError("authentication required", 16)
	}
	username, _ := ctx.Value(runtime.RUNTIME_CTX_USERNAME).(string)

	var req SubmitScoreRequest
	if err := json.Unmarshal([]byte(payload), &req); err != nil {
		return "", runtime.NewError("invalid json", 3)
	}
	if req.LevelOwnerID == "" || req.LevelKey == "" {
		return "", runtime.NewError("level_owner_id and level_key are required", 3)
	}
	if req.TimeMs <= 0 {
		return "", runtime.NewError("time_ms must be positive", 3) // INVALID_ARGUMENT
	}
	if req.SlideCount < 0 {
		return "", runtime.NewError("slide_count must be non-negative", 3) // INVALID_ARGUMENT
	}

	// Verify the level exists and is published before creating a leaderboard.
	objects, err := nk.StorageRead(ctx, []*runtime.StorageRead{
		{Collection: LevelCollection, Key: LevelStorageKey, UserID: req.LevelOwnerID},
	})
	if err != nil {
		logger.Error("storage read error verifying level for score: %v", err)
		return "", runtime.NewError("failed to verify level", 13)
	}
	levelFound := false
	if len(objects) > 0 && strings.TrimSpace(objects[0].Value) != "" {
		allLevels, parseErr := parseStoredLevels(objects[0].Value)
		if parseErr != nil {
			return "", runtime.NewError("level not found", 5)
		}
		for _, level := range allLevels {
			if levelKey(level) == req.LevelKey {
				// Allow score submission for published levels, or for the owner playing their own unpublished level.
				if isPublishedLevel(level) || req.LevelOwnerID == userID {
					levelFound = true
				}
				break
			}
		}
	}
	// Default (campaign) levels are embedded in the binary and never written to
	// storage. Fall back to them when the owner is the caller.
	if !levelFound && req.LevelOwnerID == userID {
		for _, level := range loadDefaultLevels(logger) {
			if levelKey(level) == req.LevelKey {
				levelFound = true
				break
			}
		}
	}
	if !levelFound {
		return "", runtime.NewError("level not found or not published", 5) // NOT_FOUND
	}

	leaderboardID := req.LevelOwnerID + "_" + req.LevelKey

	// Create leaderboard if it doesn't exist (idempotent)
	if err := nk.LeaderboardCreate(ctx, leaderboardID, true, "asc", "best", "", nil, true); err != nil {
		logger.Error("leaderboard create error: %v", err)
		return "", runtime.NewError("failed to create leaderboard", 13)
	}

	// Write the score (time_ms as score, slide_count as subscore)
	metadata := map[string]interface{}{
		"time_ms":     req.TimeMs,
		"slide_count": req.SlideCount,
	}
	if _, err := nk.LeaderboardRecordWrite(ctx, leaderboardID, userID, username, req.TimeMs, req.SlideCount, metadata, nil); err != nil {
		logger.Error("leaderboard write error: %v", err)
		return "", runtime.NewError("failed to submit score", 13)
	}

	// Get the player's rank
	var rank int64
	_, ownerRecords, _, _, err := nk.LeaderboardRecordsList(ctx, leaderboardID, []string{userID}, 1, "", 0)
	if err != nil {
		logger.Error("leaderboard list error: %v", err)
		return "", runtime.NewError("failed to get rank", 13)
	}
	if len(ownerRecords) > 0 {
		rank = ownerRecords[0].Rank
	}

	resp, _ := json.Marshal(map[string]interface{}{
		"rank":        rank,
		"time_ms":     req.TimeMs,
		"slide_count": req.SlideCount,
	})
	return string(resp), nil
}

// ── Get Leaderboard ──────────────────────────────────────────────────────────

func rpcGetLeaderboard(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	userID, ok := ctx.Value(runtime.RUNTIME_CTX_USER_ID).(string)
	if !ok || userID == "" {
		return "", runtime.NewError("authentication required", 16)
	}

	var req GetLeaderboardRequest
	if err := json.Unmarshal([]byte(payload), &req); err != nil {
		return "", runtime.NewError("invalid json", 3)
	}
	if req.LevelOwnerID == "" || req.LevelKey == "" {
		return "", runtime.NewError("level_owner_id and level_key are required", 3)
	}

	leaderboardID := req.LevelOwnerID + "_" + req.LevelKey
	entries := []LeaderboardEntry{}
	var playerRank int64
	var bestTimeMs int64
	var bestSlideCount int64
	var playCount int64

	switch req.Filter {
	case "all_time", "":
		records, _, nextCursor, _, err := nk.LeaderboardRecordsList(ctx, leaderboardID, nil, 10, "", 0)
		if err != nil {
			if !isLeaderboardNotFoundError(err) {
				logger.Error("leaderboard list error: %v", err)
			}
			break
		}
		if len(records) > 0 {
			bestTimeMs = records[0].Score
			bestSlideCount = records[0].Subscore
		}
		for _, r := range records {
			entries = append(entries, LeaderboardEntry{
				Rank:       r.Rank,
				Username:   r.Username.GetValue(),
				TimeMs:     r.Score,
				SlideCount: r.Subscore,
			})
			playCount += leaderboardRecordPlayCount(r)
		}

		for nextCursor != "" {
			pageRecords, _, pageNextCursor, _, pageErr := nk.LeaderboardRecordsList(ctx, leaderboardID, nil, 100, nextCursor, 0)
			if pageErr != nil {
				if !isLeaderboardNotFoundError(pageErr) {
					logger.Error("leaderboard list error: %v", pageErr)
				}
				break
			}
			for _, r := range pageRecords {
				playCount += leaderboardRecordPlayCount(r)
			}
			nextCursor = pageNextCursor
		}

		_, ownerRecords, _, _, err2 := nk.LeaderboardRecordsList(ctx, leaderboardID, []string{userID}, 1, "", 0)
		if err2 == nil && len(ownerRecords) > 0 {
			playerRank = ownerRecords[0].Rank
		}

	case "this_week":
		now := time.Now().UTC()
		weekday := int(now.Weekday())
		if weekday == 0 {
			weekday = 7
		}
		weekStart := time.Date(now.Year(), now.Month(), now.Day()-(weekday-1), 0, 0, 0, 0, time.UTC)

		records, _, _, _, err := nk.LeaderboardRecordsList(ctx, leaderboardID, nil, 100, "", 0)
		if err != nil {
			if !isLeaderboardNotFoundError(err) {
				logger.Error("leaderboard list error: %v", err)
			}
			break
		}
		var rank int64
		for _, r := range records {
			if r.UpdateTime == nil {
				continue
			}
			t := r.UpdateTime.AsTime()
			if t.Before(weekStart) {
				continue
			}
			rank++
			if r.OwnerId == userID {
				playerRank = rank
			}
			if rank <= 10 {
				entries = append(entries, LeaderboardEntry{
					Rank:       rank,
					Username:   r.Username.GetValue(),
					TimeMs:     r.Score,
					SlideCount: r.Subscore,
				})
			}
		}

	case "friends":
		friendState := 0
		friends, _, err := nk.FriendsList(ctx, userID, 100, &friendState, "")
		if err != nil {
			logger.Error("friends list error: %v", err)
			break
		}
		ownerIDs := []string{userID}
		for _, f := range friends {
			if u := f.GetUser(); u != nil {
				ownerIDs = append(ownerIDs, u.Id)
			}
		}
		_, ownerRecords, _, _, err2 := nk.LeaderboardRecordsList(ctx, leaderboardID, ownerIDs, 0, "", 0)
		if err2 != nil {
			if !isLeaderboardNotFoundError(err2) {
				logger.Error("leaderboard list error: %v", err2)
			}
			break
		}
		sort.Slice(ownerRecords, func(i, j int) bool {
			return ownerRecords[i].Score < ownerRecords[j].Score
		})
		for i, r := range ownerRecords {
			rank := int64(i + 1)
			if r.OwnerId == userID {
				playerRank = rank
			}
			entries = append(entries, LeaderboardEntry{
				Rank:       rank,
				Username:   r.Username.GetValue(),
				TimeMs:     r.Score,
				SlideCount: r.Subscore,
			})
		}
	}

	out, _ := json.Marshal(GetLeaderboardResponse{
		Entries:        entries,
		PlayerRank:     playerRank,
		BestTimeMs:     bestTimeMs,
		BestSlideCount: bestSlideCount,
		PlayCount:      playCount,
	})
	return string(out), nil
}
