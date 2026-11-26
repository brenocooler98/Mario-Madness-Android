package mobile;

import flixel.FlxCamera;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.graphics.frames.FlxFrame;
import haxe.crypto.Base64;
import openfl.display.BitmapData;
import openfl.display.PNGEncoderOptions;
import openfl.geom.Point;

class ControlsOverlay
{
	public static var active(default, null):Bool = false;

	static var sentImages:Map<String, Bool> = new Map<String, Bool>();
	static var lastOps:String = '';
	static var topLeft:Point = new Point();
	static var bottomRight:Point = new Point();

	public static function setActive(value:Bool):Void
	{
		if (active == value)
			return;
		active = value;
		MobileControls.setCamerasVisible(!value);
		if (!value && lastOps != '')
		{
			lastOps = '';
			WindowMover.setControls('');
		}
	}

	public static function update():Void
	{
		if (!active || FlxG.game == null)
			return;

		var ops:StringBuf = new StringBuf();
		for (button in MobileInput.getButtons())
			addSprite(ops, button);
		for (button in MobileButton.all)
			addSprite(ops, button);

		var text:String = ops.toString();
		if (text == lastOps)
			return;
		lastOps = text;
		WindowMover.setControls(text);
	}

	static function addSprite(ops:StringBuf, sprite:FlxSprite):Void
	{
		if (sprite == null || !sprite.exists || !sprite.visible || sprite.alpha <= 0.01 || sprite.frame == null)
			return;

		var camera:FlxCamera = sprite.getCameras()[0];
		if (camera == null || !MobileControls.isMobileCamera(camera))
			return;

		var owner = Std.isOfType(sprite, TouchButton) ? cast(sprite, TouchButton).owner : cast(sprite, MobileButton).owner;
		if (owner != null && owner != FlxG.state && !isSubState(owner))
			return;

		var key:String = imageKey(sprite.frame);
		if (!sentImages.exists(key))
		{
			var bitmap:BitmapData = sprite.frame.paint();
			var bytes = bitmap.encode(bitmap.rect, new PNGEncoderOptions(true));
			bitmap.dispose();
			if (bytes == null)
				return;
			WindowMover.addImage(key, Base64.encode(bytes));
			sentImages.set(key, true);
		}

		var scaleX:Float = FlxG.scaleMode.scale.x;
		var scaleY:Float = FlxG.scaleMode.scale.y;
		var drawWidth:Float = sprite.frameWidth * sprite.scale.x;
		var drawHeight:Float = sprite.frameHeight * sprite.scale.y;
		var worldX:Float = sprite.x - sprite.offset.x + (sprite.frameWidth - drawWidth) / 2;
		var worldY:Float = sprite.y - sprite.offset.y + (sprite.frameHeight - drawHeight) / 2;
		topLeft.setTo((camera.x + worldX * camera.zoom) * scaleX, (camera.y + worldY * camera.zoom) * scaleY);
		bottomRight.setTo((camera.x + (worldX + drawWidth) * camera.zoom) * scaleX, (camera.y + (worldY + drawHeight) * camera.zoom) * scaleY);
		var a:Point = FlxG.game.localToGlobal(topLeft);
		var b:Point = FlxG.game.localToGlobal(bottomRight);

		ops.add(key);
		ops.add('|');
		ops.add(Math.round(a.x));
		ops.add('|');
		ops.add(Math.round(a.y));
		ops.add('|');
		ops.add(Math.round(b.x));
		ops.add('|');
		ops.add(Math.round(b.y));
		ops.add('|');
		ops.add(Math.round(sprite.alpha * 255));
		ops.add('\n');
	}

	static function isSubState(owner:flixel.FlxState):Bool
	{
		var state:flixel.FlxState = FlxG.state;
		while (state != null)
		{
			if (state == owner)
				return true;
			state = state.subState;
		}
		return false;
	}

	static function imageKey(frame:FlxFrame):String
	{
		var graphicKey:String = frame.parent != null && frame.parent.key != null ? frame.parent.key : 'graphic';
		return graphicKey + '#' + (frame.name != null ? frame.name : '') + '#' + Std.int(frame.frame.x) + ',' + Std.int(frame.frame.y);
	}

	public static function reset():Void
	{
		sentImages.clear();
		lastOps = '';
		WindowMover.clearImages();
	}
}
