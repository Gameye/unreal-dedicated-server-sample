using UnrealBuildTool;

public class DedicatedServerSampleTarget : TargetRules
{
	public DedicatedServerSampleTarget(TargetInfo Target) : base(Target)
	{
		Type = TargetType.Game;
		DefaultBuildSettings = BuildSettingsVersion.Latest;
		IncludeOrderVersion = EngineIncludeOrderVersion.Latest;
		ExtraModuleNames.Add("DedicatedServerSample");
	}
}
