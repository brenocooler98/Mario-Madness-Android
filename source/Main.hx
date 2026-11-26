package;

import flixel.FlxCamera;
import flixel.FlxG;
import flixel.FlxGame;
import flixel.FlxState;
import flixel.addons.transition.FlxTransitionableState;
import openfl.Assets;
import openfl.Lib;
import openfl.display.FPS;
import openfl.display.Sprite;
import openfl.events.Event;
import openfl.system.System;
#if android
import androidmanager.callback.Callback;
import androidmanager.view.Window;
import haxe.CallStack;
import mobile.StorageUtil;
import openfl.events.UncaughtErrorEvent;
import sys.FileSystem;
import sys.io.File;
#end
#if mobile
import mobile.MobileInput;
import mobile.MobileWindow;
#end
#if cpp
import cpp.vm.Gc;
#elseif hl
import hl.Gc;
#elseif java
import java.vm.Gc;
#elseif neko
import neko.vm.Gc;
#end

class Main extends Sprite {
	public static var initialState:Class<FlxState> = TitleState; // The FlxState the game starts with.
	public static var gameWidth:Int = initialState == TitleState ? 921 : 1280; // Width of the game in pixels (might be less / more in actual pixels depending on your zoom).
	public static var gameHeight:Int = initialState == TitleState ? 691 : 720; // Height of the game in pixels (might be less / more in actual pixels depending on your zoom).
	var zoom:Float = -1; // If -1, zoom is automatically calculated to fit the window dimensions.
	var framerate:Int = 60; // How many frames per second the game should run at.
	var skipSplash:Bool = true; // Whether to skip the flixel splash screen that appears in release mode.
	var startFullscreen:Bool = false; // Whether to start the game in fullscreen on desktop targets

	public static var fpsVar:FPS;

	public static var skipNextDump:Bool = false;
	public static var forceNoVramSprites:Bool = #if (desktop && !web) false #else true #end;

	public static function main():Void {
		Lib.current.addChild(new Main());
	}

	public function new() {
		super();

		if (stage != null) {
			init();
		}
		else {
			addEventListener(Event.ADDED_TO_STAGE, init);
		}
	}

	private function init(?E:Event):Void {
		if (hasEventListener(Event.ADDED_TO_STAGE)) {
			removeEventListener(Event.ADDED_TO_STAGE, init);
		}

		setupGame();
	}

	public function setupGame():Void {
		Lib.application.window.onClose.add(PlayState.onWinClose);

		#if !debug
		initialState = TitleState;
		#end
		FlxTransitionableState.skipNextTransOut = true;
		fpsVar = new FPS(10, 4, 0xFFFFFF);

		if (fpsVar != null) {
			fpsVar.visible = false;
		}
		#if LAZY_LIBRARIES
		registerLibraries(['shared', 'songs', 'videos']);
		#end
		#if android
		Lib.current.loaderInfo.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR, onCrash);
		#end
		addChild(new FlxGame(gameWidth, gameHeight, initialState, framerate, framerate, skipSplash, startFullscreen));

		FlxG.signals.preStateSwitch.add(function () {
			if (!Main.skipNextDump) {
				Paths.clearStoredMemory(true);
			}
			clearMajor();
		});
		FlxG.signals.postStateSwitch.add(function () {
			Paths.clearUnusedMemory();
			clearMajor();
			Main.skipNextDump = false;
		});

		addChild(fpsVar);
		#if html5
		FlxG.autoPause = false;
		#end

		#if android
		Window.keepScreenOn = true;
		Window.immersive = true;
		Callback.init();
		Callback.onPause.add(onAppPause);
		FlxG.android.preventDefaultKeys = [BACK];
		#end
		#if mobile
		MobileInput.init();
		MobileWindow.init(this, gameWidth, gameHeight);
		#end

		FlxG.signals.gameResized.add(onResizeGame);
	}

	#if android
	function onAppPause():Void
	{
		if (Std.isOfType(FlxG.state, PlayState) && FlxG.state.subState == null)
			MobileInput.inject(PAUSE);
	}

	function onCrash(event:UncaughtErrorEvent):Void
	{
		var message:String = Std.string(event.error) + '\n\n' + CallStack.toString(CallStack.exceptionStack(true));

		try
		{
			File.saveContent(StorageUtil.getCrashPath() + 'crash-' + Date.now().getTime() + '.txt', message);
		}
		catch (e:Dynamic) {}

		lime.app.Application.current.window.alert(message, "FNF: Mario Madness crashed");
		Sys.exit(1);
	}
	#end

	#if LAZY_LIBRARIES
	static function registerLibraries(ids:Array<String>):Void
	{
		@:privateAccess for (id in ids)
		{
			if (lime.utils.Assets.libraries.exists(id))
				continue;

			try
			{
				var path:String = lime.utils.Assets.libraryPaths.exists(id) ? lime.utils.Assets.libraryPaths.get(id) : id;
				var manifest = lime.utils.AssetManifest.fromFile(path, haxe.io.Path.directory(path));
				if (manifest == null)
					continue;

				var library = lime.utils.AssetLibrary.fromManifest(manifest);
				if (library == null)
					continue;

				lime.utils.Assets.registerLibrary(id, library);
				library.load();
			}
			catch (e:Dynamic) {}
		}
	}
	#end

	function onResizeGame(w:Int, h:Int) {
		fixShaderSize(this);
		if (FlxG.game != null) fixShaderSize(FlxG.game);

		if (FlxG.cameras == null) return;
		for (cam in FlxG.cameras.list) {
			@:privateAccess
			if (cam != null && (cam.filters != null || cam.filters != []))
				fixShaderSize(cam.flashSprite);
		}	
	}

	function fixShaderSize(sprite:Sprite) // Shout out to Ne_Eo for bringing this to my attention
	{
		@:privateAccess {
			if (sprite != null)
			{
				sprite.__cacheBitmap = null;
				sprite.__cacheBitmapData = null;
				sprite.__cacheBitmapData2 = null;
				sprite.__cacheBitmapData3 = null;
				sprite.__cacheBitmapColorTransform = null;
			}
		}
	}

	public static function clearMajor() {
		#if cpp
		Gc.run(true);
		Gc.compact();
		#elseif hl
		Gc.major();
		#elseif (java || neko)
		Gc.run(true);
		#end
	}
}

