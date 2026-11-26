package;

import Conductor.BPMChangeEvent;
import flixel.FlxBasic;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxSubState;

class MusicBeatSubstate extends FlxSubState
{
	public function new()
	{
		super();
	}

	private var lastBeat:Float = 0;
	private var lastStep:Float = 0;

	private var curStep:Int = 0;
	private var curBeat:Int = 0;
	private var controls(get, never):Controls;

	inline function get_controls():Controls
		return PlayerSettings.player1.controls;

	#if mobile
	public var hitbox:mobile.Hitbox;
	public var backButton:mobile.MobileButton;
	public var pauseButton:mobile.MobileButton;

	var mobileCamera:flixel.FlxCamera;

	function getMobileCamera():flixel.FlxCamera
	{
		if (mobileCamera == null)
			mobileCamera = mobile.MobileControls.createCamera();
		return mobileCamera;
	}
	#end

	public function enableTouchMenu():Void
	{
		#if mobile
		mobile.MobileInput.addSwipeState(this);
		#end
	}

	public function addBackButton():Void
	{
		#if mobile
		backButton = mobile.MobileControls.createBackButton(this, getMobileCamera());
		add(backButton);
		#end
	}

	public function addPauseButton():Void
	{
		#if mobile
		pauseButton = mobile.MobileControls.createPauseButton(this, getMobileCamera());
		add(pauseButton);
		#end
	}

	public function addHitbox(withDodge:Bool = false, dodgeOnTop:Bool = false):Void
	{
		#if mobile
		hitbox = mobile.MobileControls.createHitbox(this, getMobileCamera(), withDodge, dodgeOnTop);
		add(hitbox);
		#end
	}

	#if mobile
	var touchArrows:Array<mobile.TouchButton> = [];
	#end

	public function addTouchArrows(?y:Float):Void
	{
		#if mobile
		var camera = getMobileCamera();
		var size:Int = 130;
		var posY:Float = y != null ? y : camera.height - size - 20;
		var left = new mobile.TouchButton(20, posY, size, size, 0xFF8E1C1C, UI_LEFT, ARROW(-90));
		var right = new mobile.TouchButton(40 + size, posY, size, size, 0xFF8E1C1C, UI_RIGHT, ARROW(90));
		for (button in [left, right])
		{
			button.owner = this;
			button.cameras = [camera];
			mobile.MobileInput.addBlocker(button);
			touchArrows.push(button);
			add(button);
		}
		#end
	}

	public function setTouchArrowsVisible(value:Bool):Void
	{
		#if mobile
		for (button in touchArrows)
			button.visible = value;
		#end
	}

	public function setTouchControlsVisible(value:Bool):Void
	{
		#if mobile
		if (hitbox != null)
			hitbox.visible = value;
		if (backButton != null)
			backButton.visible = value;
		if (pauseButton != null)
			pauseButton.visible = value;
		#end
	}

	function touchList(items:Array<Dynamic>, selected:Int, change:Int->Void):Void
	{
		#if mobile
		mobile.MobileControls.handleList(this, cast items, selected, change);
		#end
	}

	function touchTap(?object:flixel.FlxBasic, control:Controls.Control):Bool
	{
		#if mobile
		return mobile.MobileControls.handleTap(this, object, control);
		#else
		return false;
		#end
	}

	function touchTapped(?object:flixel.FlxBasic):Bool
	{
		#if mobile
		return this == mobile.MobileInput.topState() && mobile.TouchUtil.tapped(object, mobile.TouchUtil.getStateCamera(this));
		#else
		return false;
		#end
	}

	function clicked(?object:flixel.FlxBasic):Bool
	{
		#if mobile
		return touchTapped(object);
		#else
		return FlxG.mouse.justPressed && (object == null || FlxG.mouse.overlaps(object));
		#end
	}

	function touchConfirm(?object:flixel.FlxBasic):Bool
	{
		#if mobile
		return this == mobile.MobileInput.topState() && mobile.TouchUtil.doubleTapped(object, mobile.TouchUtil.getStateCamera(this));
		#else
		return false;
		#end
	}

	function confirmClicked(?object:flixel.FlxBasic):Bool
	{
		#if mobile
		return touchConfirm(object);
		#else
		return FlxG.mouse.justPressed && (object == null || FlxG.mouse.overlaps(object));
		#end
	}

	function touchScroll():Float
	{
		#if mobile
		return this == mobile.MobileInput.topState() ? mobile.TouchUtil.scrollDelta() : 0;
		#else
		return 0;
		#end
	}

	function touchPressed(object:flixel.FlxBasic):Bool
	{
		#if mobile
		return this == mobile.MobileInput.topState() && mobile.TouchUtil.pressed(object, mobile.TouchUtil.getStateCamera(this));
		#else
		return false;
		#end
	}

	function restoreMobileCamera():Void
	{
		#if mobile
		if (mobileCamera != null && !FlxG.cameras.list.contains(mobileCamera))
		{
			mobile.MobileControls.destroyCamera(mobileCamera);
			mobileCamera = mobile.MobileControls.createCamera();
			if (backButton != null)
				backButton.cameras = [mobileCamera];
			if (pauseButton != null)
				pauseButton.cameras = [mobileCamera];
			if (hitbox != null)
				hitbox.forEach(function(button) button.cameras = [mobileCamera]);
			for (button in touchArrows)
				button.cameras = [mobileCamera];
		}
		#end
	}

	override function closeSubState()
	{
		super.closeSubState();
		restoreMobileCamera();
	}

	override function destroy()
	{
		#if mobile
		mobile.MobileInput.removeSwipeState(this);
		for (button in touchArrows)
			mobile.MobileInput.removeBlocker(button);
		mobile.MobileControls.destroyCamera(mobileCamera);
		mobileCamera = null;
		#end
		super.destroy();
	}

	override function update(elapsed:Float)
	{
		// everyStep();
		var oldStep:Int = curStep;

		updateCurStep();
		curBeat = Math.floor(curStep / 4);

		if (oldStep != curStep && curStep > 0)
			stepHit();

		super.update(elapsed);
	}

	private function updateCurStep():Void
	{
		var lastChange:BPMChangeEvent = {
			stepTime: 0,
			songTime: 0,
			bpm: 0
		}
		for (i in 0...Conductor.bpmChangeMap.length)
		{
			if (Conductor.songPosition > Conductor.bpmChangeMap[i].songTime)
				lastChange = Conductor.bpmChangeMap[i];
		}

		curStep = lastChange.stepTime + Math.floor((Conductor.songPosition - lastChange.songTime) / Conductor.stepCrochet);
	}

	public function stepHit():Void
	{
		if (curStep % 4 == 0)
			beatHit();
	}

	public function beatHit():Void
	{
		// do literally nothing dumbass
	}
}
