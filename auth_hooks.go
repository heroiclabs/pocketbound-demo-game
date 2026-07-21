package main

import (
	"context"
	"database/sql"
	"strings"

	goaway "github.com/Remesh/go-away"
	"github.com/heroiclabs/nakama-common/api"
	"github.com/heroiclabs/nakama-common/runtime"
)

func beforeAuthenticateEmail(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, in *api.AuthenticateEmailRequest) (*api.AuthenticateEmailRequest, error) {
	if in.Username != "" {
		in.Username = normalizeUsername(in.Username)
		if goaway.IsProfane(in.Username) {
			return nil, runtime.NewError("Username contains prohibited content", 3)
		}
	}
	return in, nil
}

func beforeUpdateAccount(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, in *api.UpdateAccountRequest) (*api.UpdateAccountRequest, error) {
	if in.Username != nil {
		in.Username.Value = normalizeUsername(in.Username.Value)
		if goaway.IsProfane(in.Username.Value) {
			return nil, runtime.NewError("Username contains prohibited content", 3)
		}
	}
	return in, nil
}

func afterAuthenticateEmail(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, out *api.Session, in *api.AuthenticateEmailRequest) error {
	// Existing accounts may still carry mixed-case usernames from older builds.
	// Normalize them lazily on successful login.
	if out == nil || out.Created {
		return nil
	}

	userID, _ := ctx.Value(runtime.RUNTIME_CTX_USER_ID).(string)
	username, _ := ctx.Value(runtime.RUNTIME_CTX_USERNAME).(string)
	if userID == "" || username == "" {
		return nil
	}

	normalized := normalizeUsername(username)
	if normalized == username {
		return nil
	}

	const maxAttempts = 16
	for attempt := 0; attempt < maxAttempts; attempt++ {
		candidate := buildLowercaseUsernameCandidate(normalized, userID, attempt)
		taken, err := usernameExistsForOtherUser(ctx, db, userID, candidate)
		if err != nil {
			logger.Warn("Could not check username availability for user %s on login: %v", userID, err)
			return nil
		}
		if taken {
			continue
		}

		result, err := db.ExecContext(
			ctx,
			"UPDATE users SET username = $2, update_time = now() WHERE id = $1::uuid AND username = $3",
			userID,
			candidate,
			username,
		)
		if err != nil {
			// In the unlikely event of a race, try the next fallback candidate.
			if strings.Contains(strings.ToLower(err.Error()), "duplicate key") {
				continue
			}
			logger.Warn("Could not normalize username for user %s on login: %v", userID, err)
			return nil
		}

		rowsAffected, err := result.RowsAffected()
		if err != nil || rowsAffected == 0 {
			return nil
		}
		return nil
	}
	logger.Warn("Could not find available lowercase username for user %s on login", userID)
	return nil
}
