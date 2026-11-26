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

	public static function isMobileCamera(camera:FlxCamera):Bool
	{
		return mobileCameras.contains(camera);
	}

	public static function createCamera():FlxCamera
	{
		var rect:flixel.math.FlxRect = MobileWindow.getVisibleRect();
		var camera:FlxCamera = new FlxCamera(Std.int(rect.x), Std.int(rect.y), Std.int(Math.max(1, rect.width)), Std.int(Math.max(1, rect.height)));
		rect.put();
		camera.bgColor = FlxColor.TRANSPARENT;
		FlxG.cameras.add(camera, false);
		mobileCameras.push(camera);
		return camera;
	}

	public static function destroyCamera(camera:FlxCamera):Void
	{
		mobileCameras.remove(camera);
		if (camera != null && FlxG.cameras.list.contains(camera))
			FlxG.cameras.remove(camera);
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

		var index:Int = TouchUtil.tappedIndex(items, TouchUtil.getStateCamera(owner));
		if (index == -1)
			return;

		if (index == selected)
			MobileInput.inject(ACCEPT);
		else
			change(index - selected);
	}

	public static function handleTap(owner:FlxState, ?object:FlxBasic, control:Control):Bool
	{
		if (owner != MobileInput.topState() || !TouchUtil.tapped(object, TouchUtil.getStateCamera(owner)))
			return false;
		MobileInput.inject(control);
		return true;
	}
}
