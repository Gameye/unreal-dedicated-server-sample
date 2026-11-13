#include "SampleGameMode.h"

#include "Engine/World.h"
#include "GameFramework/PlayerController.h"
#include "GameFramework/PlayerState.h"
#include "HAL/PlatformMisc.h"
#include "Kismet/GameplayStatics.h"
#include "TimerManager.h"

DEFINE_LOG_CATEGORY(LogSampleServer);

void ASampleGameMode::InitGame(const FString& MapName, const FString& Options, FString& ErrorMessage)
{
	Super::InitGame(MapName, Options, ErrorMessage);
	MatchSeconds = UGameplayStatics::GetIntOption(Options, TEXT("MatchSeconds"), 0);
	bQuitWhenEmpty = !UGameplayStatics::HasOption(Options, TEXT("KeepAlive"));
}

void ASampleGameMode::StartPlay()
{
	Super::StartPlay();
	if (GetNetMode() != NM_DedicatedServer)
	{
		return;
	}

	// The net driver is listening by now. Logs go to stdout with -log, and
	// stdout is what Gameye's logs endpoint returns.
	UE_LOG(LogSampleServer, Display, TEXT("READY port=%d map=%s"), GetWorld()->URL.Port, *GetWorld()->GetMapName());

	if (MatchSeconds > 0)
	{
		GetWorldTimerManager().SetTimer(MatchTimer, FTimerDelegate::CreateWeakLambda(this, [this] { EndMatch(TEXT("time limit")); }), MatchSeconds, false);
	}
}

void ASampleGameMode::PostLogin(APlayerController* NewPlayer)
{
	Super::PostLogin(NewPlayer);
	bAnyPlayerJoined = true;
	++Players;
	UE_LOG(LogSampleServer, Display, TEXT("JOIN %s players=%d"), *GetNameSafe(NewPlayer->PlayerState), Players);
}

void ASampleGameMode::Logout(AController* Exiting)
{
	if (Cast<APlayerController>(Exiting))
	{
		Players = FMath::Max(0, Players - 1);
		UE_LOG(LogSampleServer, Display, TEXT("LEAVE %s players=%d"), *GetNameSafe(Exiting->PlayerState), Players);
	}
	Super::Logout(Exiting);

	if (bQuitWhenEmpty && bAnyPlayerJoined && Players == 0)
	{
		EndMatch(TEXT("all players left"));
	}
}

void ASampleGameMode::EndMatch(const FString& Reason)
{
	if (bMatchEnded)
	{
		return;
	}
	bMatchEnded = true;
	UE_LOG(LogSampleServer, Display, TEXT("MATCH_END reason=\"%s\""), *Reason);
	ReportResults(Reason);

	// Quit. The process exits, the Gameye session ends and billing stops.
	// Don't travel back to a lobby map: start a new session for the next match.
	FPlatformMisc::RequestExit(false);
}

void ASampleGameMode::EndPlay(const EEndPlayReason::Type EndPlayReason)
{
	// Gameye stops a session with SIGTERM (DELETE /session/{id} or ttl expiry),
	// then SIGKILL 50 seconds later. Unreal on Linux turns SIGTERM into a normal
	// quit, so this runs on that path too.
	if (EndPlayReason == EEndPlayReason::Quit && !bMatchEnded)
	{
		bMatchEnded = true;
		UE_LOG(LogSampleServer, Display, TEXT("SHUTDOWN reason=\"stop signal\""));
		ReportResults(TEXT("stopped"));
	}
	Super::EndPlay(EndPlayReason);
}

void ASampleGameMode::ReportResults(const FString& Reason)
{
	// Send the match result to your own backend here, and keep it to a few
	// seconds. The server never holds a Gameye API token: your backend talks to
	// Gameye.
	UE_LOG(LogSampleServer, Display, TEXT("RESULTS reported (%s)"), *Reason);
}
