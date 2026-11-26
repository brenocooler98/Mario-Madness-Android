package mariomadness;

import android.app.Activity;
import android.graphics.Color;
import android.view.SurfaceView;
import android.view.View;
import android.view.ViewGroup;
import android.view.ViewParent;

import java.lang.reflect.Field;

import org.haxe.extension.Extension;

public class WindowMover {
    private static volatile float targetX = 0;
    private static volatile float targetY = 0;
    private static volatile boolean pending = false;
    private static View surface = null;

    public static void setOffset(float x, float y) {
        targetX = x;
        targetY = y;

        final Activity activity = Extension.mainActivity;
        if (activity == null || pending)
            return;

        pending = true;
        activity.runOnUiThread(new Runnable() {
            @Override
            public void run() {
                pending = false;
                try {
                    View view = getSurface(activity);
                    if (view == null)
                        return;
                    view.setTranslationX(targetX);
                    view.setTranslationY(targetY);
                } catch (Exception e) {
                    e.printStackTrace();
                }
            }
        });
    }

    private static View getSurface(Activity activity) {
        if (surface != null && surface.getWindowToken() != null)
            return surface;

        surface = null;
        try {
            Class<?> sdl = Class.forName("org.libsdl.app.SDLActivity");
            Field field = sdl.getDeclaredField("mSurface");
            field.setAccessible(true);
            Object value = field.get(null);
            if (value instanceof View)
                surface = (View) value;
        } catch (Exception e) {
            surface = null;
        }

        if (surface == null)
            surface = findSurface(activity.getWindow().getDecorView());

        if (surface != null) {
            ViewParent parent = surface.getParent();
            if (parent instanceof View)
                ((View) parent).setBackgroundColor(Color.BLACK);
        }
        return surface;
    }

    private static View findSurface(View view) {
        if (view instanceof SurfaceView)
            return view;
        if (view instanceof ViewGroup) {
            ViewGroup group = (ViewGroup) view;
            for (int i = 0; i < group.getChildCount(); i++) {
                View found = findSurface(group.getChildAt(i));
                if (found != null)
                    return found;
            }
        }
        return null;
    }
}
