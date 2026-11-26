package mobile;

import Controls.Control;
import flixel.FlxBasic;
import flixel.FlxCamera;
import flixel.FlxG;
import flixel.FlxState;
import flixel.util.FlxColor;

class MobileControls
{
	static inline var MARGIN:Int = 20;

	static var mobileCameras:Array<FlxCamera> = [];
	static var camerasVisible:Bool = true;

	public static function isMobileCamera(camera:FlxCamera):Bool
	{
		return mobileCameras.contains(camera);
	}

	public static function createCamera():FlxCamera
	{
		var camera:FlxCamera = new FlxCamera(0, 0, MobileWindow.controlsWidth, MobileWindow.controlsHeight);
		camera.bgColor = FlxColor.TRANSPARENT;
		FlxG.cameras.add(camera, false);
		mobileCameras.push(camera);
		camera.visible = camerasVisible;
		layoutCamera(camera);
		return camera;
	}

	public static function destroyCamera(camera:FlxCamera):Void
	{
		mobileCameras.remove(camera);
		if (camera != null && FlxG.cameras.list.contains(camera))
			FlxG.cameras.remove(camera);
	}

	public static function setCamerasVisible(value:Bool):Void
	{
		camerasVisible = value;
		for (camera in mobileCameras)
			if (camera != null)
				camera.visible = value;
	}

	public static function layoutCameras():Void
	{
		for (camera in mobileCameras)
			if (camera != null)
				layoutCamera(camera);
	}

	static function layoutCamera(camera:FlxCamera):Void
	{
		var area:flixel.math.FlxRect = MobileWindow.getControlsArea();
		var zoom:Float = area.width / MobileWindow.controlsWidth;
		if (!Math.isFinite(zoom) || zoom <= 0)
			zoom = 1;
		var changed:Bool = camera.zoom != zoom || camera.width != MobileWindow.controlsWidth || camera.height != MobileWindow.controlsHeight;
		camera.x = area.x;
		camera.y = area.y;
		area.put();
		if (!changed)
			return;
		@:privateAccess camera.initialZoom = zoom;
		camera.width = MobileWindow.controlsWidth;
		camera.height = MobileWindow.controlsHeight;
		camera.zoom = zoom;
		camera.onResize();
	}

	public static function createBackButton(owner:FlxState, camera:FlxCamera):MobileButton
	{
		var button:MobileButton = new MobileButton('backButton', 'back', BACK, 0.65);
		button.owner = owner;
		button.setPosition(camera.width - button.width - MARGIN, camera.height - button.height - MARGIN);
		button.cameras = [camera];
		return button;
	}

	public static function createPauseButton(owner:FlxState, camera:FlxCamera):MobileButton
	{
		var button:MobileButton = new MobileButton('pauseButton', 'pause', PAUSE, 0.9);
		button.owner = owner;
		button.setPosition(camera.width - button.width - MARGIN, MARGIN);
		if (ClientPrefs.invisiblePauseButton)
			button.alpha = 0;
				button.cameras = [camera];
		return button;
	}

	public static function createHitbox(owner:FlxState, camera:FlxCamera, withDodge:Bool, dodgeOnTop:Bool, laneTop:Float = 0, invisible:Bool = false):Hitbox
	{
		var hitbox:Hitbox = new Hitbox(owner, camera.width, camera.height, withDodge, dodgeOnTop, laneTop, invisible);
		hitbox.forEach(function(button:TouchButton) button.cameras = [camera]);
		return hitbox;
	}

	public static function handleList(owner:FlxState, items:Array<FlxBasic>, selected:Int, change:Int->Void):Void
	{
		if (owner != MobileInput.topState())
			return;

		var camera:FlxCamera = TouchUtil.getStateCamera(owner);
		var index:Int = TouchUtil.tappedIndex(items, camera);
		if (index == -1)
			return;

		if (usesDoubleTap(owner))
		{
			if (index != selected)
				change(index - selected);
			if (TouchUtil.doubleTapped(items[index], camera))
				MobileInput.inject(ACCEPT);
			return;
		}

		if (index != selected)
			change(index - selected);
		else
			MobileInput.inject(ACCEPT);
	}

	public static function usesDoubleTap(owner:FlxState):Bool
	{
		return Std.isOfType(owner, MainMenuState) || Std.isOfType(owner, CustomFreeplayState);
	}

	public static function confirmTap(owner:FlxState, ?object:FlxBasic):Bool
	{
		if (owner != MobileInput.topState())
			return false;
		var camera:FlxCamera = TouchUtil.getStateCamera(owner);
		return usesDoubleTap(owner) ? TouchUtil.doubleTapped(object, camera) : TouchUtil.tapped(object, camera);
	}

	public static function handleTap(owner:FlxState, ?object:FlxBasic, control:Control):Bool
	{
		if (owner != MobileInput.topState() || !TouchUtil.tapped(object, TouchUtil.getStateCamera(owner)))
			return false;
		MobileInput.inject(control);
		return true;
	}
}
