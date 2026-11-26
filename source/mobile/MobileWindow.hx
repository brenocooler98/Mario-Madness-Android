package mobile;

import flixel.FlxCamera;
import flixel.FlxG;
import flixel.math.FlxRect;
import openfl.Lib;
import openfl.display.DisplayObject;
import openfl.display.Shape;
import openfl.geom.Point;

class MobileWindow
{
	public static var width(default, null):Int = 1280;
	public static var height(default, null):Int = 720;
	public static var displayWidth(default, null):Int = 1920;
	public static var displayHeight(default, null):Int = 1080;
	public static var x(default, null):Int = 320;
	public static var y(default, null):Int = 180;
	public static var fullscreen(default, null):Bool = false;
	public static var overscan(default, null):Float = 0;
	public static var windowed(default, null):Bool = false;

	static var target:DisplayObject;
	static var masks:Shape;
	static var initialized:Bool = false;
	static var dirty:Bool = true;

	static var viewX:Float = 0;
	static var viewY:Float = 0;
	static var viewWidth:Float = 0;
	static var viewHeight:Float = 0;
	static var offsetX:Float = 0;
	static var offsetY:Float = 0;

	static var lastStageWidth:Int = -1;
	static var lastStageHeight:Int = -1;
	static var lastRootX:Float = 0;
	static var lastRootY:Float = 0;
	static var lastRootScale:Float = 0;
	static var lastTargetX:Float = 0;
	static var lastTargetY:Float = 0;
	static var lastTargetScale:Float = 0;

	static var maskX:Float = -1;
	static var maskY:Float = -1;
	static var maskW:Float = -1;
	static var maskH:Float = -1;
	static var maskStageW:Int = -1;
	static var maskStageH:Int = -1;

	static var sentWindowed:Bool = false;
	static var sentLeft:Int = 0;
	static var sentTop:Int = 0;
	static var sentRight:Int = 0;
	static var sentBottom:Int = 0;
	static var windowSent:Bool = false;

	static var pointA:Point = new Point();
	static var pointB:Point = new Point();

	public static function init(main:DisplayObject, width:Int, height:Int):Void
	{
		target = main;
		MobileWindow.width = width;
		MobileWindow.height = height;
		dirty = true;

		if (initialized)
			return;
		initialized = true;

		masks = new Shape();
		Lib.current.stage.addChild(masks);
		FlxG.signals.preDraw.add(onPreDraw);
		FlxG.signals.gameResized.add(function(_, _) invalidate());
		FlxG.signals.preStateSwitch.add(center);
		apply();
	}

	static function onPreDraw():Void
	{
		apply();
		ControlsOverlay.update();
	}

	public static inline function invalidate():Void
	{
		dirty = true;
	}

	public static function resize(width:Int, height:Int):Void
	{
		if (width <= 0 || height <= 0)
			return;
		if (width == MobileWindow.width && height == MobileWindow.height)
			return;
		var centerX:Float = MobileWindow.x + MobileWindow.width / 2;
		var centerY:Float = MobileWindow.y + MobileWindow.height / 2;
		MobileWindow.width = width;
		MobileWindow.height = height;
		MobileWindow.x = Math.round(centerX - width / 2);
		MobileWindow.y = Math.round(centerY - height / 2);
		dirty = true;
		apply();
	}

	public static function move(x:Int, y:Int):Void
	{
		if (x == MobileWindow.x && y == MobileWindow.y)
			return;
		MobileWindow.x = x;
		MobileWindow.y = y;
		dirty = true;
	}

	public static function center():Void
	{
		x = Math.round((displayWidth - width) / 2);
		y = Math.round((displayHeight - height) / 2);
		dirty = true;
		apply();
	}

	public static function setFullscreen(value:Bool):Void
	{
		fullscreen = value;
		ScreenStyle.apply(value);
		dirty = true;
		apply();
	}

	public static function reset():Void
	{
		width = 1280;
		height = 720;
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

		var root:DisplayObject = Lib.current;
		var rootScale:Float = root.scaleX != 0 ? root.scaleX : 1;
		var rootScaleY:Float = root.scaleY != 0 ? root.scaleY : 1;

		if (!dirty && stageWidth == lastStageWidth && stageHeight == lastStageHeight && root.x == lastRootX && root.y == lastRootY && rootScale == lastRootScale
			&& target.x == lastTargetX && target.y == lastTargetY && target.scaleX == lastTargetScale)
		{
			updateOverscan(overscan);
			return;
		}
		dirty = false;
		lastStageWidth = stageWidth;
		lastStageHeight = stageHeight;
		lastRootX = root.x;
		lastRootY = root.y;
		lastRootScale = rootScale;

		var previousX:Float = FlxG.scaleMode.scale.x;
		var previousY:Float = FlxG.scaleMode.scale.y;
		FlxG.scaleMode.onMeasure(width, height);
		if (previousX != FlxG.scaleMode.scale.x || previousY != FlxG.scaleMode.scale.y)
			@:privateAccess FlxG.cameras.resize();

		var zoom:Float = Math.min(stageWidth / width, stageHeight / height);
		var cornerX:Float = (stageWidth - width * zoom) / 2;
		var cornerY:Float = (stageHeight - height * zoom) / 2;

		offsetX = Math.round((x - (displayWidth - width) / 2) * zoom);
		offsetY = Math.round((y - (displayHeight - height) / 2) * zoom);
		windowed = width != 1280 || height != 720 || offsetX != 0 || offsetY != 0;

		target.scaleX = zoom;
		target.scaleY = zoom;
		target.x = ((zoom - 1) * root.x + cornerX + offsetX) / rootScale;
		target.y = ((zoom - 1) * root.y + cornerY + offsetY) / rootScaleY;
		lastTargetX = target.x;
		lastTargetY = target.y;
		lastTargetScale = target.scaleX;

		var wide:Bool = fullscreen && !windowed && cornerX > 0;
		var extra:Float = 0;
		if (wide)
		{
			pointA.setTo(0, cornerY);
			var edge:Point = FlxG.game.globalToLocal(pointA);
			extra = Math.max(0, Math.ceil(-edge.x));
		}
		updateOverscan(wide ? extra : 0);

		var windowLeft:Float = cornerX + offsetX;
		var windowTop:Float = cornerY + offsetY;
		var windowWidth:Float = width * zoom;
		var windowHeight:Float = height * zoom;

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
			viewWidth = windowWidth;
			viewHeight = windowHeight;
			drawMasks(stageWidth, stageHeight, windowLeft, windowTop, windowWidth, windowHeight);
		}

		pointA.setTo(0, 0);
		pointB.setTo(offsetX, offsetY);
		var origin:Point = FlxG.game.globalToLocal(pointA);
		var moved:Point = FlxG.game.globalToLocal(pointB);
		MobileControls.shiftCameras(origin.x - moved.x, origin.y - moved.y);

		sendWindow(Math.floor(windowLeft), Math.floor(windowTop), Math.ceil(windowLeft + windowWidth), Math.ceil(windowTop + windowHeight));
		ControlsOverlay.setActive(windowed);
	}

	static function sendWindow(left:Int, top:Int, right:Int, bottom:Int):Void
	{
		if (windowSent && sentWindowed == windowed && (!windowed || (left == sentLeft && top == sentTop && right == sentRight && bottom == sentBottom)))
			return;
		windowSent = true;
		sentWindowed = windowed;
		sentLeft = left;
		sentTop = top;
		sentRight = right;
		sentBottom = bottom;
		WindowMover.setWindow(windowed, left, top, right, bottom);
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

		pointA.setTo(viewX + offsetX, viewY + offsetY);
		pointB.setTo(viewX + offsetX + viewWidth, viewY + offsetY + viewHeight);
		var topLeft:Point = FlxG.game.globalToLocal(pointA);
		var bottomRight:Point = FlxG.game.globalToLocal(pointB);
		return FlxRect.get(Math.round(topLeft.x), Math.round(topLeft.y), Math.round(bottomRight.x - topLeft.x), Math.round(bottomRight.y - topLeft.y));
	}

	static function drawMasks(stageWidth:Int, stageHeight:Int, x:Float, y:Float, w:Float, h:Float):Void
	{
		var parent = Lib.current.stage;
		if (masks.parent != parent || parent.getChildIndex(masks) != parent.numChildren - 1)
			parent.addChild(masks);

		if (stageWidth == maskStageW && stageHeight == maskStageH && x == maskX && y == maskY && w == maskW && h == maskH)
			return;
		maskStageW = stageWidth;
		maskStageH = stageHeight;
		maskX = x;
		maskY = y;
		maskW = w;
		maskH = h;

		var left:Float = Math.max(0, Math.min(stageWidth, x));
		var top:Float = Math.max(0, Math.min(stageHeight, y));
		var right:Float = Math.max(0, Math.min(stageWidth, x + w));
		var bottom:Float = Math.max(0, Math.min(stageHeight, y + h));

		var graphics = masks.graphics;
		graphics.clear();
		graphics.beginFill(0x000000);
		if (top > 0)
			graphics.drawRect(0, 0, stageWidth, Math.ceil(top));
		if (bottom < stageHeight)
			graphics.drawRect(0, Math.floor(bottom), stageWidth, stageHeight - Math.floor(bottom));
		if (left > 0)
			graphics.drawRect(0, top, Math.ceil(left), bottom - top);
		if (right < stageWidth)
			graphics.drawRect(Math.floor(right), top, stageWidth - Math.floor(right), bottom - top);
		graphics.endFill();
	}
}
