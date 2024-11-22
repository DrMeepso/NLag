using GDWeave;

namespace Meepso.NLag;

public class Mod : IMod {
    public Config Config;

    public Mod(IModInterface modInterface) {
        this.Config = modInterface.ReadConfig<Config>();
        modInterface.Logger.Information("Loading");

        string SteamPath = $"{Directory.GetCurrentDirectory()}\\GDWeave\\mods\\Meepso.NLag\\SteamNetwork.gd";
        // check if the file exists
        if (File.Exists(SteamPath))
        {
            modInterface.Logger.Information("SteamNetwork.gd exists");
            modInterface.RegisterScriptMod(new SteamPatch(modInterface));
        }
        else
        {
            modInterface.Logger.Information("SteamNetwork.gd does not exist");
        }

    }

    public void Dispose() {
        // Cleanup anything you do here
    }
}
