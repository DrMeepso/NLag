using GDWeave;

namespace Meepso.NLag;

public class Mod : IMod {
    public Config Config;

    public Mod(IModInterface modInterface) {
        this.Config = modInterface.ReadConfig<Config>();
        modInterface.Logger.Information("Loading");

        // disabled for now
        modInterface.RegisterScriptMod(new SteamPatch(modInterface));
    }

    public void Dispose() {
        // Cleanup anything you do here
    }
}
