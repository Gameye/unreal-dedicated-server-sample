using UnrealBuildTool;

public class DedicatedServerSampleServerTarget : TargetRules
{
	public DedicatedServerSampleServerTarget(TargetInfo Target) : base(Target)
	{
		Type = TargetType.Server;
		DefaultBuildSettings = BuildSettingsVersion.Latest;
		IncludeOrderVersion = EngineIncludeOrderVersion.Latest;
		ExtraModuleNames.Add("DedicatedServerSample");
	}
}
