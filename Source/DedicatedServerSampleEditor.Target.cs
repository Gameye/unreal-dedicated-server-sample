using UnrealBuildTool;

public class DedicatedServerSampleEditorTarget : TargetRules
{
	public DedicatedServerSampleEditorTarget(TargetInfo Target) : base(Target)
	{
		Type = TargetType.Editor;
		DefaultBuildSettings = BuildSettingsVersion.Latest;
		IncludeOrderVersion = EngineIncludeOrderVersion.Latest;
		ExtraModuleNames.Add("DedicatedServerSample");
	}
}
