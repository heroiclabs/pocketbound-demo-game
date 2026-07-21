package main

import (
	"context"
	"database/sql"

	"github.com/heroiclabs/nakama-common/runtime"
)

func init() {
	loadComponentRegistry()
}

func InitModule(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, initializer runtime.Initializer) error {
	logger.Info("heroic-brackeys server module loaded")

	if err := initializer.RegisterRpc("submit_level", rpcSubmitLevel); err != nil {
		return err
	}
	if err := initializer.RegisterRpc("get_level", rpcGetLevel); err != nil {
		return err
	}
	if err := initializer.RegisterRpc("list_my_levels", rpcListMyLevels); err != nil {
		return err
	}
	if err := initializer.RegisterRpc("list_single_player_levels", rpcListSinglePlayerLevels); err != nil {
		return err
	}
	if err := initializer.RegisterRpc("list_all_levels", rpcListAllLevels); err != nil {
		return err
	}
	if err := initializer.RegisterRpc("list_friend_levels", rpcListFriendLevels); err != nil {
		return err
	}
	if err := initializer.RegisterRpc("submit_score", rpcSubmitScore); err != nil {
		return err
	}
	if err := initializer.RegisterRpc("get_leaderboard", rpcGetLeaderboard); err != nil {
		return err
	}
	if err := initializer.RegisterRpc("submit_level_vote", rpcSubmitLevelVote); err != nil {
		return err
	}
	if err := initializer.RegisterRpc("delete_level", rpcDeleteLevel); err != nil {
		return err
	}
	if err := initializer.RegisterRpc("publish_level", rpcPublishLevel); err != nil {
		return err
	}
	if err := initializer.RegisterBeforeUpdateAccount(beforeUpdateAccount); err != nil {
		return err
	}
	if err := initializer.RegisterBeforeAuthenticateEmail(beforeAuthenticateEmail); err != nil {
		return err
	}
	if err := initializer.RegisterAfterAuthenticateEmail(afterAuthenticateEmail); err != nil {
		return err
	}

	return nil
}
