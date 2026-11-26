package mariomadness;

import android.app.Activity;
import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.PixelFormat;
import android.graphics.Rect;
import android.graphics.drawable.ColorDrawable;
import android.os.Build;
import android.util.Base64;
import android.view.SurfaceView;
import android.view.View;
import android.view.ViewGroup;
import android.view.ViewParent;
import android.view.Window;
import android.view.WindowManager;

import java.lang.reflect.Field;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;

import org.haxe.extension.Extension;

public class WindowMover {
    private static final Object lock = new Object();

    private static volatile boolean windowActive = false;
    private static volatile int clipLeft = 0;
    private static volatile int clipTop = 0;
    private static volatile int clipRight = 0;
    private static volatile int clipBottom = 0;
    private static volatile boolean windowPending = false;
    private static volatile String pendingOps = null;
    private static volatile boolean opsPending = false;

    private static boolean appliedActive = false;
    private static boolean translucent = false;
    private static View surface = null;
    private static Overlay overlay = null;

    private static final HashMap<String, Bitmap> images = new HashMap<String, Bitmap>();

    private static class Op {
        String key;
        Rect rect = new Rect();
        int alpha;
    }

    private static class Overlay extends View {
        private final Paint paint = new Paint(Paint.FILTER_BITMAP_FLAG | Paint.ANTI_ALIAS_FLAG);
        private List<Op> ops = new ArrayList<Op>();

        Overlay(Context context) {
            super(context);
            setClickable(false);
            setFocusable(false);
            setWillNotDraw(false);
        }

        void setOps(List<Op> value) {
            ops = value;
            invalidate();
        }

        @Override
        public boolean onTouchEvent(android.view.MotionEvent event) {
            return false;
        }

        @Override
        protected void onDraw(Canvas canvas) {
            synchronized (lock) {
                for (Op op : ops) {
                    Bitmap bitmap = images.get(op.key);
                    if (bitmap == null)
                        continue;
                    paint.setAlpha(op.alpha);
                    canvas.drawBitmap(bitmap, null, op.rect, paint);
                }
            }
        }
    }

    public static void setWindow(boolean active, int left, int top, int right, int bottom) {
        windowActive = active;
        clipLeft = left;
        clipTop = top;
        clipRight = right;
        clipBottom = bottom;

        final Activity activity = Extension.mainActivity;
        if (activity == null || windowPending)
            return;

        windowPending = true;
        activity.runOnUiThread(new Runnable() {
            @Override
            public void run() {
                windowPending = false;
                try {
                    applyWindow(activity);
                } catch (Exception e) {
                    e.printStackTrace();
                }
            }
        });
    }

    public static void setControls(String ops) {
        pendingOps = ops;

        final Activity activity = Extension.mainActivity;
        if (activity == null || opsPending)
            return;

        opsPending = true;
        activity.runOnUiThread(new Runnable() {
            @Override
            public void run() {
                opsPending = false;
                try {
                    applyControls(activity);
                } catch (Exception e) {
                    e.printStackTrace();
                }
            }
        });
    }

    public static void addImage(String key, String data) {
        try {
            byte[] bytes = Base64.decode(data, Base64.DEFAULT);
            Bitmap bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.length);
            if (bitmap == null)
                return;
            synchronized (lock) {
                Bitmap previous = images.put(key, bitmap);
                if (previous != null && previous != bitmap)
                    previous.recycle();
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    public static void clearImages() {
        synchronized (lock) {
            images.clear();
        }
    }

    private static void applyWindow(Activity activity) {
        View view = getSurface(activity);
        if (view == null)
            return;

        boolean active = windowActive;
        if (active)
            view.setClipBounds(new Rect(clipLeft, clipTop, clipRight, clipBottom));
        else
            view.setClipBounds(null);

        if (active != appliedActive) {
            appliedActive = active;
            setSeeThrough(activity, view, active);
        }

        Overlay layer = getOverlay(activity, view);
        if (layer != null)
            layer.setVisibility(active ? View.VISIBLE : View.GONE);
    }

    private static void applyControls(Activity activity) {
        View view = getSurface(activity);
        if (view == null)
            return;
        Overlay layer = getOverlay(activity, view);
        if (layer == null)
            return;

        String text = pendingOps;
        List<Op> ops = new ArrayList<Op>();
        if (text != null && text.length() > 0) {
            for (String line : text.split("\n")) {
                String[] parts = line.split("\\|");
                if (parts.length < 6)
                    continue;
                try {
                    Op op = new Op();
                    op.key = parts[0];
                    op.rect.set(Integer.parseInt(parts[1]), Integer.parseInt(parts[2]), Integer.parseInt(parts[3]), Integer.parseInt(parts[4]));
                    op.alpha = Math.max(0, Math.min(255, Integer.parseInt(parts[5])));
                    ops.add(op);
                } catch (NumberFormatException e) {
                }
            }
        }
        layer.setOps(ops);
    }

    private static void setSeeThrough(Activity activity, View view, boolean active) {
        Window window = activity.getWindow();
        ViewParent parent = view.getParent();

        if (active) {
            window.setFormat(PixelFormat.TRANSLUCENT);
            window.setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
            if (parent instanceof View)
                ((View) parent).setBackgroundColor(Color.TRANSPARENT);

            boolean converted = false;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                try {
                    converted = activity.setTranslucent(true);
                } catch (Exception e) {
                    converted = false;
                }
            }
            translucent = converted;
            if (!converted)
                window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WALLPAPER);
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SHOW_WALLPAPER);
            if (translucent && Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                try {
                    activity.setTranslucent(false);
                } catch (Exception e) {
                }
            }
            translucent = false;
            window.setBackgroundDrawable(new ColorDrawable(Color.BLACK));
            if (parent instanceof View)
                ((View) parent).setBackgroundColor(Color.BLACK);
            window.setFormat(PixelFormat.OPAQUE);
        }
    }

    private static Overlay getOverlay(Activity activity, View view) {
        if (overlay != null && overlay.getParent() != null)
            return overlay;
        ViewParent parent = view.getParent();
        if (!(parent instanceof ViewGroup))
            return null;
        overlay = new Overlay(activity);
        overlay.setVisibility(appliedActive ? View.VISIBLE : View.GONE);
        ((ViewGroup) parent).addView(overlay, new ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        return overlay;
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
