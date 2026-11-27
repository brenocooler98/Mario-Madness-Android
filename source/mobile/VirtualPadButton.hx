package mobile;

import Controls.Control;
import flixel.FlxG;
import flixel.graphics.FlxGraphic;
import flixel.graphics.frames.FlxAtlasFrames;
import flixel.graphics.frames.FlxFrame;
import flixel.util.FlxColor;
import openfl.display.BitmapData;

class VirtualPadButton extends TouchButton
{
	static inline var FRAMES:Int = 3;

	public function new(x:Float, y:Float, size:Int, name:String, control:Control)
	{
		super(x, y, size, size, FlxColor.TRANSPARENT, control, NONE, false);

		var graphic:FlxGraphic = getGraphic(name);
		if (graphic != null)
		{
			loadGraphic(graphic, true, Std.int(graphic.width / FRAMES), graphic.height);
			animation.add('idle', [for (i in 0...FRAMES) i], 12, true);
			animation.play('idle');
			setGraphicSize(size, size);
			updateHitbox();
		}

		idleAlpha = 0.7;
		pressedAlpha = 1;
		alpha = idleAlpha;
	}

	static function getGraphic(name:String):FlxGraphic
	{
		var key:String = 'virtualpad_$name';
		var cached:FlxGraphic = FlxG.bitmap.get(key);
		if (cached != null)
			return cached;

		var atlas:FlxAtlasFrames = Paths.getSparrowAtlas('mobile/virtualpad', 'shared');
		if (atlas == null)
			return null;
		var frame:FlxFrame = atlas.getByName(name);
		if (frame == null)
			return null;

		var bitmap:BitmapData = frame.paint();
		var graphic:FlxGraphic = FlxG.bitmap.add(bitmap, false, key);
		graphic.persist = true;
		graphic.destroyOnNoUse = false;
		return graphic;
	}

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);
		color = pressed() ? 0xFFBFBFBF : FlxColor.WHITE;
	}
}
