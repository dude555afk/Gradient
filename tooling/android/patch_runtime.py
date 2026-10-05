from pathlib import Path
import shutil

root = Path("android/app/src/main")
manifest = root / "AndroidManifest.xml"
text = manifest.read_text()

for permission in [
    "android.permission.POST_NOTIFICATIONS",
    "android.permission.FOREGROUND_SERVICE",
    "android.permission.FOREGROUND_SERVICE_DATA_SYNC",
    "android.permission.WAKE_LOCK",
]:
    if permission not in text:
        text = text.replace(
            "<application",
            f'    <uses-permission android:name="{permission}" />\n    <application',
            1,
        )

if 'android:name=".GradientApplication"' not in text:
    text = text.replace(
        "<application",
        '<application android:name=".GradientApplication"',
        1,
    )

if "GenerationForegroundService" not in text:
    service = """
        <service
            android:name=".GenerationForegroundService"
            android:stopWithTask="false"
            android:exported="false"
            android:foregroundServiceType="dataSync" />
    """
    text = text.replace("</application>", service + "\n    </application>")

manifest.write_text(text)

target = root / "kotlin/com/dude555afk/gradient"
target.mkdir(parents=True, exist_ok=True)
source = Path("tooling/android")

for name in [
    "GradientApplication.kt",
    "BackgroundRuntime.kt",
    "GenerationForegroundService.kt",
]:
    shutil.copyfile(source / name, target / name)

activity = target / "MainActivity.kt"
activity_text = activity.read_text()

if "import android.content.Context" not in activity_text:
    activity_text = activity_text.replace(
        "import android.content.Intent",
        "import android.content.Context\nimport android.content.Intent",
        1,
    )

needle = "class MainActivity : FlutterActivity() {"
if "provideFlutterEngine" not in activity_text:
    activity_text = activity_text.replace(
        needle,
        """class MainActivity : FlutterActivity() {
    override fun provideFlutterEngine(context: Context): FlutterEngine =
        (application as GradientApplication).engine

    override fun shouldDestroyEngineWithHost(): Boolean = false
""",
        1,
    )

activity.write_text(activity_text)
