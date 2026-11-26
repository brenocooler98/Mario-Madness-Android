package mobile;

import flixel.FlxCamera;
import flixel.FlxG;
import flixel.math.FlxRect;
import openfl.geom.Point;
import openfl.Lib;
import openfl.display.DisplayObject;
import openfl.display.Shape;

class MobileWindow
{
	public static var width(default, null):Int = 1280;
	public static var height(default, null):Int = 720;
	public static var displayWidth(default, null):Int = 1920;
	public static var displayHeight(default, null):Int = 1080;
	public static var x(default, null):Int = 320;
	public static var y(default, null):Int = 180;

	static var offsetX:Float = 0;
	static var offsetY:Float = 0;
	static var sentOffsetX:Float = 0;
	static var sentOffsetY:Float = 0;
	static var offsetSent:Bool = false;

	static var target:DisplayObject;
	static var masks:Shape;
	static var initialized:Bool = false;
	static var maskKey:String = '';
	public static var fullscreen(default, null):Bool = false;
	public static var overscan(default, null):Float = 0;

	static var viewX:Float = 0;
	static var viewY:Float = 0;
	static var viewWidth:Float = 0;
	static var viewHeight:Float = 0;

	public static function init(main:DisplayObject, width:Int, height:Int):Void
	{
		target = main;
		MobileWindow.width = width;
		MobileWindow.height = height;

		if (initialized)
			return;
		initialized = true;

		masks = new Shape();
		Lib.current.stage.addChild(masks);
		FlxG.signals.preDraw.add(apply);
		FlxG.signals.gameResized.add(function(_, _) apply());
		FlxG.signals.preStateSwitch.add(center);
		apply();
	}

	public static function resize(width:Int, height:Int):Void
	{
		if (width <= 0 || height <= 0)
			return;
		var centerX:Float = MobileWindow.x + MobileWindow.width / 2;
		var centerY:Float = MobileWindow.y + MobileWindow.height / 2;
		MobileWindow.width = width;
		MobileWindow.height = height;
		MobileWindow.x = Math.round(centerX - width / 2);
		MobileWindow.y = Math.round(centerY - height / 2);
		apply();
	}

	public static function move(x:Int, y:Int):Void
	{
		MobileWindow.x = x;
		MobileWindow.y = y;
		apply();
	}

	public static function center():Void
	{
		x = Math.round((displayWidth - width) / 2);
		y = Math.round((displayHeight - height) / 2);
		apply();
	}

	public static function setFullscreen(value:Bool):Void
	{
		fullscreen = value;
		ScreenStyle.apply(value);
		apply();
	}

	public static function reset():Void
	{
		resize(1280, 720);
		center();
	}

	static function apply():Void
	{
		if (target == null || FlxG.game == null || FlxG.scaleMode == null)
			return;

		var stageWidth:Int = Lib.current.stage.stageWidth;
		var stageHeight:Int = Lib.current.stage.stageHeight;
		if (stageWidth <= 0 || stageHeight <= 0)
			return;

		var previousX:Float = FlxG.scaleMode.scale.x;
		var previousY:Float = FlxG.scaleMode.scale.y;
		FlxG.scaleMode.onMeasure(width, height);
		if (previousX != FlxG.scaleMode.scale.x || previousY != FlxG.scaleMode.scale.y)
			@:privateAccess FlxG.cameras.resize();

		var zoom:Float = Math.min(stageWidth / width, stageHeight / height);
		var cornerX:Float = (stageWidth - width * zoom) / 2;
		var cornerY:Float = (stageHeight - height * zoom) / 2;

		var root:DisplayObject = Lib.current;
		var rootScale:Float = root.scaleX != 0 ? root.scaleX : 1;
		var rootScaleY:Float = root.scaleY != 0 ? root.scaleY : 1;

		target.scaleX = zoom;
		target.scaleY = zoom;
		target.x = ((zoom - 1) * root.x + cornerX) / rootScale;
		target.y = ((zoom - 1) * root.y + cornerY) / rootScaleY;

		var wide:Bool = fullscreen && width == 1280 && height == 720 && cornerX > 0;
		var extra:Float = 0;
		if (wide)
		{
			var edge:Point = FlxG.game.globalToLocal(new Point(0, cornerY));
			extra = Math.max(0, Math.ceil(-edge.x));
		}
		updateOverscan(wide ? extra : 0);
		updateOffset(zoom);

		if (wide && extra > 0)
		{
			viewX = 0;
			viewY = cornerY;
			viewWidth = stageWidth;
			viewHeight = height * zoom;
			drawMasks(stageWidth, stageHeight, 0, cornerY, stageWidth, height * zoom);
		}
		else
		{
			viewX = cornerX;
			viewY = cornerY;
			viewWidth = width * zoom;
			viewHeight = height * zoom;
			drawMasks(stageWidth, stageHeight, cornerX, cornerY, width * zoom, height * zoom);
		}
	}

	static function updateOffset(zoom:Float):Void
	{
		offsetX = Math.round((x - (displayWidth - width) / 2) * zoom);
		offsetY = Math.round((y - (displayHeight - height) / 2) * zoom);

		var origin:Point = FlxG.game.globalToLocal(new Point(0, 0));
		var moved:Point = FlxG.game.globalToLocal(new Point(offsetX, offsetY));
		MobileControls.shiftCameras(origin.x - moved.x, origin.y - moved.y);

		if (offsetSent && offsetX == sentOffsetX && offsetY == sentOffsetY)
			return;
		offsetSent = true;
		sentOffsetX = offsetX;
		sentOffsetY = offsetY;
		WindowMover.setOffset(offsetX, offsetY);
	}

	static function updateOverscan(extra:Float):Void
	{
		overscan = extra;
		for (camera in FlxG.cameras.list)
		{
			if (camera == null || MobileControls.isMobileCamera(camera))
				continue;

			var fits:Bool = camera.x == 0 && camera.width == FlxG.width;
			var value:Float = fits ? extra : 0;
			if (camera.overscan != value)
				camera.overscan = value;
		}
	}

	public static function getVisibleRect():FlxRect
	{
		apply();

		if (FlxG.game == null || viewWidth <= 0 || viewHeight <= 0)
			return FlxRect.get(0, 0, FlxG.width, FlxG.height);

		var topLeft:Point = FlxG.game.globalToLocal(new Point(viewX, viewY));
		var bottomRight:Point = FlxG.game.globalToLocal(new Point(viewX + viewWidth, viewY + viewHeight));
		return FlxRect.get(Math.round(topLeft.x), Math.round(topLeft.y), Math.round(bottomRight.x - topLeft.x), Math.round(bottomRight.y - topLeft.y));
	}

	static function drawMasks(stageWidth:Int, stageHeight:Int, x:Float, y:Float, w:Float, h:Float):Void
	{
		var parent = Lib.current.stage;
		if (masks.parent != parent || parent.getChildIndex(masks) != parent.numChildren - 1)
			parent.addChild(masks);

		var key:String = stageWidth + ':' + stageHeight + ':' + x + ':' + y + ':' + w + ':' + h;
		if (key == maskKey)
			return;
		maskKey = key;

		var graphics = masks.graphics;
		graphics.clear();
		graphics.beginFill(0x000000);
		if (y > 0)
		{
			graphics.drawRect(0, 0, stageWidth, Math.ceil(y));
			graphics.drawRect(0, Math.floor(y + h), stageWidth, stageHeight - Math.floor(y + h));
		}
		if (x > 0)
		{
			graphics.drawRect(0, 0, Math.ceil(x), stageHeight);
			graphics.drawRect(Math.floor(x + w), 0, stageWidth - Math.floor(x + w), stageHeight);
		}
		graphics.endFill();
	}
}
