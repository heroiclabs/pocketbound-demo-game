package main

import (
	"context"
	"database/sql"
	"strconv"
	"strings"
)

func normalizeUsername(username string) string {
	return strings.ToLower(username)
}

func truncateString(s string, maxLen int) string {
	if maxLen <= 0 {
		return ""
	}
	runes := []rune(s)
	if len(runes) <= maxLen {
		return s
	}
	return string(runes[:maxLen])
}

func buildLowercaseUsernameCandidate(baseUsername string, userID string, attempt int) string {
	const maxUsernameLength = 128
	base := truncateString(normalizeUsername(baseUsername), maxUsernameLength)
	if attempt <= 0 {
		return base
	}

	idToken := strings.ReplaceAll(strings.ToLower(userID), "-", "")
	if idToken == "" {
		idToken = "user"
	}

	if attempt == 1 {
		baseLimit := maxUsernameLength - 1 - len(idToken)
		if baseLimit < 0 {
			baseLimit = 0
		}
		return truncateString(base, baseLimit) + "_" + idToken
	}

	suffix := strconv.Itoa(attempt - 1)
	baseLimit := maxUsernameLength - 1 - len(idToken) - 1 - len(suffix)
	if baseLimit < 0 {
		baseLimit = 0
	}
	return truncateString(base, baseLimit) + "_" + idToken + "_" + suffix
}

func usernameExistsForOtherUser(ctx context.Context, db *sql.DB, userID string, username string) (bool, error) {
	var exists bool
	if err := db.QueryRowContext(
		ctx,
		"SELECT EXISTS(SELECT 1 FROM users WHERE username = $1 AND id <> $2::uuid)",
		username,
		userID,
	).Scan(&exists); err != nil {
		return false, err
	}
	return exists, nil
}
