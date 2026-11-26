package mobile;

import flixel.FlxBasic;
import flixel.FlxCamera;
import flixel.FlxG;
import flixel.input.touch.FlxTouch;
import flixel.math.FlxPoint;

enum SwipeDirection
{
	UP;
	DOWN;
	LEFT;
	RIGHT;
}

class TouchUtil
{
	public static var tapDistance:Float = 30;

	public static var verticalStep:Float = 70;
	public static var horizontalStep:Float = 110;

	public static var flingSpeed:Float = 1400;
	public static var flingMaxSteps:Int = 10;

	static var anchors:Map<Int, FlxPoint> = new Map<Int, FlxPoint>();
	static var lastPositions:Map<Int, FlxPoint> = new Map<Int, FlxPoint>();
	static var velocities:Map<Int, FlxPoint> = new Map<Int, FlxPoint>();
	static var steps:Array<SwipeDirection> = [];
	static var dragged:Array<Int> = [];

	static var scrollTouch:Int = -1;
	static var scrollLastY:Float = 0;
	static var scrollVelocity:Float = 0;
	static var scrollFrameDelta:Float = 0;

	static var flingDirection:Null<SwipeDirection> = null;
	static var flingRemaining:Int = 0;
	static var flingDelay:Float = 0;
	static var flingTimer:Float = 0;

	public static function updateDrags():Void
	{
		steps.resize(0);

		var elapsed:Float = FlxG.elapsed > 0 ? FlxG.elapsed : 1 / 60;
		var active:Array<Int> = [];

		for (touch in FlxG.touches.list)
		{
			if (touch.justPressed)
				stopFling();

			var id:Int = touch.touchPointID;
			if (!touch.pressed && !touch.justReleased)
				continue;
			active.push(id);

			var anchor:FlxPoint = anchors.get(id);
			if (anchor == null || touch.justPressed)
			{
				if (anchor != null)
					anchor.put();
				anchors.set(id, FlxPoint.get(touch.viewX, touch.viewY));
				setPoint(lastPositions, id, touch.viewX, touch.viewY);
				setPoint(velocities, id, 0, 0);
				dragged.remove(id);
				continue;
			}

			var last:FlxPoint = lastPositions.get(id);
			var velocity:FlxPoint = velocities.get(id);
			if (last != null && velocity != null)
			{
				var vx:Float = (touch.viewX - last.x) / elapsed;
				var vy:Float = (touch.viewY - last.y) / elapsed;
				velocity.set(velocity.x * 0.4 + vx * 0.6, velocity.y * 0.4 + vy * 0.6);
				last.set(touch.viewX, touch.viewY);
			}

			var dx:Float = touch.viewX - anchor.x;
			var dy:Float = touch.viewY - anchor.y;

			if (Math.abs(dy) >= Math.abs(dx))
			{
				while (Math.abs(dy) >= verticalStep)
				{
					var sign:Int = dy < 0 ? -1 : 1;
					steps.push(sign < 0 ? UP : DOWN);
					markDragged(id);
					anchor.y += sign * verticalStep;
					dy -= sign * verticalStep;
				}
			}
			else
			{
				while (Math.abs(dx) >= horizontalStep)
				{
					var sign:Int = dx < 0 ? -1 : 1;
					steps.push(sign < 0 ? LEFT : RIGHT);
					markDragged(id);
					anchor.x += sign * horizontalStep;
					dx -= sign * horizontalStep;
				}
			}

			if (touch.justReleased && dragged.contains(id) && velocity != null)
				startFling(velocity);
		}

		for (id in [for (key in anchors.keys()) key])
		{
			if (!active.contains(id))
			{
				anchors.get(id).put();
				anchors.remove(id);
				dragged.remove(id);
				removePoint(lastPositions, id);
				removePoint(velocities, id);
			}
		}

		updateFling(elapsed);
		updateScroll(elapsed);
	}

	static function updateScroll(elapsed:Float):Void
	{
		scrollFrameDelta = 0;

		var current:FlxTouch = null;
		for (touch in FlxG.touches.list)
		{
			if (touch.touchPointID == scrollTouch && (touch.pressed || touch.justReleased))
			{
				current = touch;
				break;
			}
		}

		if (current == null)
		{
			scrollTouch = -1;
			for (touch in FlxG.touches.list)
			{
				if (touch.justPressed && !MobileInput.isBlocked(touch))
				{
					scrollTouch = touch.touchPointID;
					scrollLastY = touch.viewY;
					scrollVelocity = 0;
					return;
				}
			}

			if (Math.abs(scrollVelocity) > 5)
			{
				scrollFrameDelta = scrollVelocity * elapsed;
				scrollVelocity *= Math.pow(0.05, elapsed);
			}
			else
				scrollVelocity = 0;
			return;
		}

		var delta:Float = current.viewY - scrollLastY;
		scrollLastY = current.viewY;
		scrollFrameDelta = delta;
		if (elapsed > 0)
			scrollVelocity = scrollVelocity * 0.5 + (delta / elapsed) * 0.5;

		if (current.justReleased)
			scrollTouch = -1;
	}

	public static function scrollDelta():Float
	{
		return scrollFrameDelta;
	}

	static function markDragged(id:Int):Void
	{
		if (!dragged.contains(id))
			dragged.push(id);
	}

	static function setPoint(map:Map<Int, FlxPoint>, id:Int, x:Float, y:Float):Void
	{
		var point:FlxPoint = map.get(id);
		if (point == null)
			map.set(id, FlxPoint.get(x, y));
		else
			point.set(x, y);
	}

	static function removePoint(map:Map<Int, FlxPoint>, id:Int):Void
	{
		var point:FlxPoint = map.get(id);
		if (point != null)
			point.put();
		map.remove(id);
	}

	static function startFling(velocity:FlxPoint):Void
	{
		var vertical:Bool = Math.abs(velocity.y) >= Math.abs(velocity.x);
		var speed:Float = vertical ? Math.abs(velocity.y) : Math.abs(velocity.x);
		if (speed < flingSpeed)
			return;

		var step:Float = vertical ? verticalStep : horizontalStep;
		flingRemaining = Std.int(Math.min(flingMaxSteps, Math.round(speed / (step * 10))));
		if (flingRemaining <= 0)
			return;

		flingDirection = vertical ? (velocity.y < 0 ? UP : DOWN) : (velocity.x < 0 ? LEFT : RIGHT);
		flingDelay = 0.04;
		flingTimer = flingDelay;
	}

	static function updateFling(elapsed:Float):Void
	{
		if (flingDirection == null)
			return;

		flingTimer -= elapsed;
		if (flingTimer > 0)
			return;

		steps.push(flingDirection);
		flingRemaining--;
		flingDelay *= 1.35;
		flingTimer = flingDelay;

		if (flingRemaining <= 0)
			stopFling();
	}

	public static function stopFling():Void
	{
		flingDirection = null;
		flingRemaining = 0;
	}

	public static function swipe(direction:SwipeDirection):Bool
	{
		return steps.contains(direction);
	}

	public static function swipeCount(direction:SwipeDirection):Int
	{
		var count:Int = 0;
		for (step in steps)
			if (step == direction)
				count++;
		return count;
	}

	public static function isDragging():Bool
	{
		for (touch in FlxG.touches.list)
			if (touch.pressed && dragged.contains(touch.touchPointID))
				return true;
		return false;
	}

	static function isTap(touch:FlxTouch):Bool
	{
		if (!touch.justReleased || dragged.contains(touch.touchPointID) || MobileInput.isBlocked(touch))
			return false;
		var dx:Float = touch.viewX - touch.justPressedPosition.x;
		var dy:Float = touch.viewY - touch.justPressedPosition.y;
		return Math.sqrt(dx * dx + dy * dy) <= tapDistance;
	}

	public static function tapped(?object:FlxBasic, ?camera:FlxCamera):Bool
	{
		for (touch in FlxG.touches.list)
		{
			if (!isTap(touch))
				continue;
			if (object == null)
				return true;
			if (touch.overlaps(object, getCamera(object, camera)))
				return true;
		}
		return false;
	}

	public static function justTouched(object:FlxBasic, ?camera:FlxCamera):Bool
	{
		for (touch in FlxG.touches.list)
			if (touch.justPressed && touch.overlaps(object, getCamera(object, camera)))
				return true;
		return false;
	}

	public static function pressed(object:FlxBasic, ?camera:FlxCamera):Bool
	{
		for (touch in FlxG.touches.list)
			if (touch.pressed && !MobileInput.isBlocked(touch) && touch.overlaps(object, getCamera(object, camera)))
				return true;
		return false;
	}

	public static function tappedIndex(objects:Array<FlxBasic>, ?camera:FlxCamera):Int
	{
		for (i in 0...objects.length)
		{
			var object:FlxBasic = objects[i];
			if (object != null && object.exists && object.visible && tapped(object, camera))
				return i;
		}
		return -1;
	}

	static function getCamera(object:FlxBasic, ?fallback:FlxCamera):FlxCamera
	{
		@:privateAccess var own:Array<FlxCamera> = object._cameras;
		if (own != null && own.length > 0)
			return own[0];
		if (fallback != null)
			return fallback;
		var cameras:Array<FlxCamera> = object.getCameras();
		return cameras != null && cameras.length > 0 ? cameras[0] : FlxG.camera;
	}

	public static function getStateCamera(state:flixel.FlxState):FlxCamera
	{
		var cameras:Array<FlxCamera> = state.getCameras();
		return cameras != null && cameras.length > 0 ? cameras[0] : FlxG.camera;
	}
}
