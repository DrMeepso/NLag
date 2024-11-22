using GDWeave;
using GDWeave.Godot;
using GDWeave.Modding;
using GDWeave.Godot.Variants;


namespace Meepso.NLag;

public class SteamPatch : IScriptMod
{

    public IModInterface modInterface;
    public SteamPatch(IModInterface modInterface)
    {
        this.modInterface = modInterface;
    }

    public IEnumerable<Token> CreatePrintFunction(string message, int indent)
    {
        yield return new Token(TokenType.Newline, (uint)indent);
        yield return new Token(TokenType.BuiltInFunc, (int)BuiltinFunction.TextPrint);
        yield return new Token(TokenType.ParenthesisOpen);
        yield return new ConstantToken(new StringVariant(message));
        yield return new Token(TokenType.ParenthesisClose);
        yield return new Token(TokenType.Newline, (uint)indent);
    }

    public bool ShouldRun(string path) => path == "res://Scenes/Singletons/SteamNetwork.gdc";

    public IEnumerable<Token> Modify(string path, IEnumerable<Token> tokens)
    {

        modInterface.Logger.Information("Patching SteamNetwork.gd...");

        var _readyMatch = new MultiTokenWaiter([
            t => t is IdentifierToken { Name: "_ready"},
            t => t.Type is TokenType.ParenthesisOpen,
            t => t.Type is TokenType.ParenthesisClose,
            t => t.Type is TokenType.Colon,
            t => t is Token { Type: TokenType.Newline, AssociatedData: 1 }
        ]);

        var _processMatch = new MultiTokenWaiter([
            t => t is IdentifierToken { Name: "_process"},
            t => t.Type is TokenType.ParenthesisOpen,
            t => t is IdentifierToken { Name: "delta"},
            t => t.Type is TokenType.ParenthesisClose,
            t => t.Type is TokenType.Colon,
            t => t is Token { Type: TokenType.Newline, AssociatedData: 1 }
        ]);

        // func _read_all_P2P_packets(channel = 0, read_count = 0):
        var __read_all_P2P_packetsMatch = new MultiTokenWaiter([
            t => t is IdentifierToken { Name: "_read_all_P2P_packets"},
            t => t.Type is TokenType.ParenthesisOpen,
            t => t is IdentifierToken { Name: "channel"},
            t => t.Type is TokenType.OpAssign,
            t => t is ConstantToken,
            t => t.Type is TokenType.Comma,
            t => t is IdentifierToken { Name: "read_count"},
            t => t.Type is TokenType.OpAssign,
            t => t is ConstantToken,
            t => t.Type is TokenType.ParenthesisClose,
            t => t.Type is TokenType.Colon,
            t => t is Token { Type: TokenType.Newline, AssociatedData: 1 }
        ]);

        // need to replace the tokens after the match
        // func _read_P2P_Packet(
        var _read_P2P_PacketMatch = new MultiTokenWaiter([
            t => t.Type is TokenType.PrFunction,
            t => t is IdentifierToken { Name: "_read_P2P_Packet"},
            t => t.Type is TokenType.ParenthesisOpen,
            t => t is IdentifierToken { Name: "channel" },
        ]);

        // need to replace a variable declaration
        // var PACKET_SIZE: int =
        // skip next 6 tokens
        var PacketSizeMatch = new MultiTokenWaiter([
            t => t.Type is TokenType.PrVar,
            t => t is IdentifierToken { Name: "PACKET_SIZE"},
            t => t.Type is TokenType.Colon,
            t => t.Type is TokenType.BuiltInType, // int
            t => t.Type is TokenType.OpAssign,
            t => t is IdentifierToken { Name: "Steam"},
        ]);

        int lineNumber = 0;
        int i = 0;

        int skipNextN = 0;
        foreach (Token token in tokens)
        {
            if (token.Type == TokenType.Newline)
            {
                lineNumber++;
            }
            i++;
            //modInterface.Logger.Information($"[{lineNumber}/{i}] Token: {token}");

            // check if we are in the ready function
            if (_readyMatch.Check(token))
            {

                // add a print statement
                // print("SteamNetwork ready!")
                foreach (var printToken in CreatePrintFunction("SteamNetwork ready!", 1))
                    yield return printToken;

                // create the new thread
                // steamPacketThread = Thread.new()
                yield return new IdentifierToken("steamPacketThread");
                yield return new Token(TokenType.OpAssign);
                yield return new IdentifierToken("Thread");
                yield return new Token(TokenType.Period);
                yield return new IdentifierToken("new");
                yield return new Token(TokenType.ParenthesisOpen);
                yield return new Token(TokenType.ParenthesisClose);
                yield return new Token(TokenType.Newline, 1);

                // steamPacketThread.start(self, "_steam_packet_thread", null)
                yield return new IdentifierToken("steamPacketThread");
                yield return new Token(TokenType.Period);
                yield return new IdentifierToken("start");
                yield return new Token(TokenType.ParenthesisOpen);
                yield return new Token(TokenType.Self);
                yield return new Token(TokenType.Comma);
                yield return new ConstantToken(new StringVariant("_steam_packet_thread"));
                yield return new Token(TokenType.Comma);
                yield return new ConstantToken(new NilVariant());
                yield return new Token(TokenType.ParenthesisClose);
                yield return new Token(TokenType.Newline, 1);
            }

            if (_processMatch.Check(token))
            {
                /*
    if not STEAM_ENABLED: return 
	Steam.run_callbacks()
	_run_all_buffered_packets()
                */

                yield return new Token(TokenType.Newline, 1); // just make sure

                // if not STEAM_ENABLED: return
                yield return new Token(TokenType.CfIf);
                yield return new Token(TokenType.OpNot);
                yield return new IdentifierToken("STEAM_ENABLED");
                yield return new Token(TokenType.Colon);
                yield return new Token(TokenType.CfReturn);
                yield return new Token(TokenType.Newline, 1);

                // Steam.run_callbacks()
                yield return new IdentifierToken("Steam");
                yield return new Token(TokenType.Period);
                yield return new IdentifierToken("run_callbacks");
                yield return new Token(TokenType.ParenthesisOpen);
                yield return new Token(TokenType.ParenthesisClose);
                yield return new Token(TokenType.Newline, 1);

                // _run_all_buffered_packets()
                yield return new IdentifierToken("_run_all_buffered_packets");
                yield return new Token(TokenType.ParenthesisOpen);
                yield return new Token(TokenType.ParenthesisClose);
                yield return new Token(TokenType.Newline, 1);

                // return, make sure non of the original code runs
                yield return new Token(TokenType.CfReturn);
                yield return new Token(TokenType.Newline, 0);

            }

            if (__read_all_P2P_packetsMatch.Check(token))
            {
                /*
    if Steam.getAvailableP2PPacketSize(channel) > 0:
	    _read_steam_packet(channel)
	    if not steamThreadRunning: return
	    _read_all_P2P_packets(channel, read_count + 1)
                */

                yield return new Token(TokenType.Newline, 1); // just make sure

                // if Steam.getAvailableP2PPacketSize(channel) > 0:
                yield return new Token(TokenType.CfIf);
                yield return new IdentifierToken("Steam");
                yield return new Token(TokenType.Period);
                yield return new IdentifierToken("getAvailableP2PPacketSize");
                yield return new Token(TokenType.ParenthesisOpen);
                yield return new IdentifierToken("channel");
                yield return new Token(TokenType.ParenthesisClose);
                yield return new Token(TokenType.OpGreater);
                yield return new ConstantToken(new IntVariant(0));
                yield return new Token(TokenType.Colon);

                yield return new Token(TokenType.Newline, 2); // inside the if
                
                // _read_steam_packet(channel)
                yield return new IdentifierToken("_read_steam_packet");
                yield return new Token(TokenType.ParenthesisOpen);
                yield return new IdentifierToken("channel");
                yield return new Token(TokenType.ParenthesisClose);

                yield return new Token(TokenType.Newline, 2); // inside the if

                // if not steamThreadRunning: return
                yield return new Token(TokenType.CfIf);
                yield return new Token(TokenType.OpNot);
                yield return new IdentifierToken("steamThreadRunning");
                yield return new Token(TokenType.Colon);
                yield return new Token(TokenType.CfReturn);

                yield return new Token(TokenType.Newline, 2); // inside the if

                // _read_all_P2P_packets(channel, read_count + 1)
                yield return new IdentifierToken("_read_all_P2P_packets");
                yield return new Token(TokenType.ParenthesisOpen);
                yield return new IdentifierToken("channel");
                yield return new Token(TokenType.Comma);
                yield return new IdentifierToken("read_count");
                yield return new Token(TokenType.OpAdd);
                yield return new ConstantToken(new IntVariant(1));
                yield return new Token(TokenType.ParenthesisClose);

                yield return new Token(TokenType.Newline, 1); // exit the if

                // return, make sure non of the original code runs
                yield return new Token(TokenType.CfReturn);

                yield return new Token(TokenType.Newline, 0); // exit the function

            }

            if (_read_P2P_PacketMatch.Check(token))
            {

                skipNextN = 3; // skip the next 3 tokens

                // add a identifier for the packet parameter
                yield return new IdentifierToken("PACKET");

            }

            if (PacketSizeMatch.Check(token))
            {
                skipNextN = 6; // skip the next 6 tokens
                // make the variable equal to 1
                yield return new ConstantToken(new IntVariant(1));
            }

            // get the next token

            if (token.Type == TokenType.PrVar && tokens.ElementAtOrDefault(i) is IdentifierToken { Name: "PACKET" })
            {
                skipNextN = 13; // skip the next 13 tokens
            }

            // dont end the file, we want to add more stuff
            if (token.Type == TokenType.Eof || skipNextN > 0)
            {
                // do nothing
                skipNextN--;
            } else
            {
                yield return token;
            }
        }

        // var bufferedPackets = []
        yield return new Token(TokenType.Newline);
        yield return new Token(TokenType.PrVar);
        yield return new IdentifierToken("bufferedPackets");
        yield return new Token(TokenType.OpAssign);
        yield return new Token(TokenType.BracketOpen);
        yield return new Token(TokenType.BracketClose);

        yield return new Token(TokenType.Newline);

        // var steamThreadRunning = true
        yield return new Token(TokenType.Newline);
        yield return new Token(TokenType.PrVar);
        yield return new IdentifierToken("steamThreadRunning");
        yield return new Token(TokenType.OpAssign);
        yield return new ConstantToken(new BoolVariant(true));
        yield return new Token(TokenType.Newline);

        // var steamPacketThread
        yield return new Token(TokenType.Newline);
        yield return new Token(TokenType.PrVar);
        yield return new IdentifierToken("steamPacketThread");

        /*
func _steam_packet_thread():
	print("Steam thead online!")
	
	while steamThreadRunning:
		if STEAM_LOBBY_ID <= 0: continue
		
		for channel in CHANNELS.size():
			if not steamThreadRunning: break
			_read_all_P2P_packets(channel)
	OS.delay_msec(16)
*/

                // func _steam_packet_thread():
                yield return new Token(TokenType.Newline);
        yield return new Token(TokenType.PrFunction);
        yield return new IdentifierToken("_steam_packet_thread");
        yield return new Token(TokenType.ParenthesisOpen);
        yield return new Token(TokenType.ParenthesisClose);
        yield return new Token(TokenType.Colon);

        yield return new Token(TokenType.Newline, 1); // we are inside the function

        // print the function start
        foreach (var printToken in CreatePrintFunction("Steam thead online!", 1))
            yield return printToken;

        // while steamThreadRunning:
        yield return new Token(TokenType.CfWhile);
        yield return new IdentifierToken("steamThreadRunning");
        yield return new Token(TokenType.Colon);

        yield return new Token(TokenType.Newline, 2); // we are inside the while loop

        // if STEAM_LOBBY_ID <= 0: continue
        yield return new Token(TokenType.CfIf);
        yield return new IdentifierToken("STEAM_LOBBY_ID");
        yield return new Token(TokenType.OpLessEqual);
        yield return new ConstantToken(new IntVariant(0));
        yield return new Token(TokenType.Colon);
        yield return new Token(TokenType.CfContinue);

        yield return new Token(TokenType.Newline, 2); // we are inside the while loop

        // for channel in CHANNELS.size():
        yield return new Token(TokenType.CfFor);
        yield return new IdentifierToken("channel");
        yield return new Token(TokenType.OpIn);
        yield return new IdentifierToken("CHANNELS");
        yield return new Token(TokenType.Period);
        yield return new IdentifierToken("size");
        yield return new Token(TokenType.ParenthesisOpen);
        yield return new Token(TokenType.ParenthesisClose);
        yield return new Token(TokenType.Colon);

        yield return new Token(TokenType.Newline, 3); // we are inside the for loop

        // if not steamThreadRunning: break
        yield return new Token(TokenType.CfIf);
        yield return new Token(TokenType.OpNot);
        yield return new IdentifierToken("steamThreadRunning");
        yield return new Token(TokenType.Colon);
        yield return new Token(TokenType.CfBreak);

        yield return new Token(TokenType.Newline, 3); // we are inside the for loop

        // _read_all_P2P_packets(channel)
        yield return new IdentifierToken("_read_all_P2P_packets");
        yield return new Token(TokenType.ParenthesisOpen);
        yield return new IdentifierToken("channel");
        yield return new Token(TokenType.ParenthesisClose);

        yield return new Token(TokenType.Newline, 2); // exit the for loop back to the while loop

        // OS.delay_msec(16)
        yield return new IdentifierToken("OS");
        yield return new Token(TokenType.Period);
        yield return new IdentifierToken("delay_msec");
        yield return new Token(TokenType.ParenthesisOpen);
        yield return new ConstantToken(new IntVariant(16));
        yield return new Token(TokenType.ParenthesisClose);

        yield return new Token(TokenType.Newline, 0); // the function is done!

        /*
        func _read_steam_packet(channel):
            var PACKET_SIZE = Steam.getAvailableP2PPacketSize(channel)

            if PACKET_SIZE > 0:
                var PACKET = Steam.readP2PPacket(PACKET_SIZE, channel)
                bufferedPackets.append(PACKET)
        */

        // func _read_steam_packet(channel):
        yield return new Token(TokenType.Newline);
        yield return new Token(TokenType.PrFunction);
        yield return new IdentifierToken("_read_steam_packet");
        yield return new Token(TokenType.ParenthesisOpen);
        yield return new IdentifierToken("channel");
        yield return new Token(TokenType.ParenthesisClose);
        yield return new Token(TokenType.Colon);

        yield return new Token(TokenType.Newline, 1); // we are inside the function

        // var PACKET_SIZE = Steam.getAvailableP2PPacketSize(channel)
        yield return new Token(TokenType.PrVar);
        yield return new IdentifierToken("PACKET_SIZE");
        yield return new Token(TokenType.OpAssign);
        yield return new IdentifierToken("Steam");
        yield return new Token(TokenType.Period);
        yield return new IdentifierToken("getAvailableP2PPacketSize");
        yield return new Token(TokenType.ParenthesisOpen);
        yield return new IdentifierToken("channel");
        yield return new Token(TokenType.ParenthesisClose);

        yield return new Token(TokenType.Newline, 1); // we are inside the function

        // if PACKET_SIZE > 0:
        yield return new Token(TokenType.CfIf);
        yield return new IdentifierToken("PACKET_SIZE");
        yield return new Token(TokenType.OpGreater);
        yield return new ConstantToken(new IntVariant(0));
        yield return new Token(TokenType.Colon);

        yield return new Token(TokenType.Newline, 2); // we are inside the if

        // var PACKET = Steam.readP2PPacket(PACKET_SIZE, channel)
        yield return new Token(TokenType.PrVar);
        yield return new IdentifierToken("PACKET");
        yield return new Token(TokenType.OpAssign);
        yield return new IdentifierToken("Steam");
        yield return new Token(TokenType.Period);
        yield return new IdentifierToken("readP2PPacket");
        yield return new Token(TokenType.ParenthesisOpen);
        yield return new IdentifierToken("PACKET_SIZE");
        yield return new Token(TokenType.Comma);
        yield return new IdentifierToken("channel");
        yield return new Token(TokenType.ParenthesisClose);

        yield return new Token(TokenType.Newline, 2); // we are inside the if

        // bufferedPackets.append(PACKET)
        yield return new IdentifierToken("bufferedPackets");
        yield return new Token(TokenType.Period);
        yield return new IdentifierToken("append");
        yield return new Token(TokenType.ParenthesisOpen);
        yield return new IdentifierToken("PACKET");
        yield return new Token(TokenType.ParenthesisClose);

        yield return new Token(TokenType.Newline, 0); // the function is done!

        /*
        func _run_all_buffered_packets():
            if len(bufferedPackets) > 0:
                for packet in bufferedPackets:
                    _read_P2P_Packet(packet)

                bufferedPackets.clear()
        */

        // func _run_all_buffered_packets():
        yield return new Token(TokenType.Newline);

        yield return new Token(TokenType.PrFunction);
        yield return new IdentifierToken("_run_all_buffered_packets");
        yield return new Token(TokenType.ParenthesisOpen);
        yield return new Token(TokenType.ParenthesisClose);
        yield return new Token(TokenType.Colon);

        yield return new Token(TokenType.Newline, 1); // we are inside the function

        // if len(bufferedPackets) > 0:
        yield return new Token(TokenType.CfIf);
        yield return new Token(TokenType.BuiltInFunc, (int)BuiltinFunction.Len);
        yield return new Token(TokenType.ParenthesisOpen);
        yield return new IdentifierToken("bufferedPackets");
        yield return new Token(TokenType.ParenthesisClose);
        yield return new Token(TokenType.OpGreater);
        yield return new ConstantToken(new IntVariant(0));
        yield return new Token(TokenType.Colon);

        yield return new Token(TokenType.Newline, 2); // we are inside the if

        // for packet in bufferedPackets:
        yield return new Token(TokenType.CfFor);
        yield return new IdentifierToken("packet");
        yield return new Token(TokenType.OpIn);
        yield return new IdentifierToken("bufferedPackets");
        yield return new Token(TokenType.Colon);

        yield return new Token(TokenType.Newline, 3); // we are inside the for loop

        // _read_P2P_Packet(packet)
        yield return new IdentifierToken("_read_P2P_Packet");
        yield return new Token(TokenType.ParenthesisOpen);
        yield return new IdentifierToken("packet");
        yield return new Token(TokenType.ParenthesisClose);

        yield return new Token(TokenType.Newline, 2); // exit the for loop

        // bufferedPackets.clear()
        yield return new IdentifierToken("bufferedPackets");
        yield return new Token(TokenType.Period);
        yield return new IdentifierToken("clear");
        yield return new Token(TokenType.ParenthesisOpen);
        yield return new Token(TokenType.ParenthesisClose);

        // end the function
        yield return new Token(TokenType.Newline, 0);

        /*
        func _exit_tree():
            steamThreadRunning = false
            steamPacketThread.wait_to_finish()
        */

        // func _exit_tree():
        yield return new Token(TokenType.Newline);

        yield return new Token(TokenType.PrFunction);
        yield return new IdentifierToken("_exit_tree");
        yield return new Token(TokenType.ParenthesisOpen);
        yield return new Token(TokenType.ParenthesisClose);
        yield return new Token(TokenType.Colon);

        yield return new Token(TokenType.Newline, 1); // we are inside the function

        // steamThreadRunning = false
        yield return new IdentifierToken("steamThreadRunning");
        yield return new Token(TokenType.OpAssign);
        yield return new ConstantToken(new BoolVariant(false));

        yield return new Token(TokenType.Newline, 1); // we are inside the function

        // steamPacketThread.wait_to_finish()
        yield return new IdentifierToken("steamPacketThread");
        yield return new Token(TokenType.Period);
        yield return new IdentifierToken("wait_to_finish");
        yield return new Token(TokenType.ParenthesisOpen);
        yield return new Token(TokenType.ParenthesisClose);

        yield return new Token(TokenType.Newline, 0); // the function is done!

        // all done!

        yield return new Token(TokenType.Eof);
    }
}