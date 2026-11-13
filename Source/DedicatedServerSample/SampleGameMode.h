#pragma once

#include "CoreMinimal.h"
#include "GameFramework/GameModeBase.h"
#include "SampleGameMode.generated.h"

DECLARE_LOG_CATEGORY_EXTERN(LogSampleServer, Log, All);

// One match per server process. The server logs READY when it accepts
// connections, logs each JOIN and LEAVE, and quits when the match ends.
// Quitting ends the Gameye session, which stops billing.
//
// Map options, passed in the session's args:
//   ?MatchSeconds=600   end the match after this many seconds (0 = no limit)
//   ?KeepAlive          don't quit when the last player leaves
UCLASS()
class ASampleGameMode : public AGameModeBase
{
	GENERATED_BODY()

public:
	virtual void InitGame(const FString& MapName, const FString& Options, FString& ErrorMessage) override;
	virtual void StartPlay() override;
	virtual void PostLogin(APlayerController* NewPlayer) override;
	virtual void Logout(AController* Exiting) override;
	virtual void EndPlay(const EEndPlayReason::Type EndPlayReason) override;

private:
	void EndMatch(const FString& Reason);
	void ReportResults(const FString& Reason);

	int32 MatchSeconds = 0;
	int32 Players = 0;
	bool bQuitWhenEmpty = true;
	bool bAnyPlayerJoined = false;
	bool bMatchEnded = false;
	FTimerHandle MatchTimer;
};
