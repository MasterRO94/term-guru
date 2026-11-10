package dev.termguru;

import com.intellij.ide.AppLifecycleListener;

import javax.swing.SwingUtilities;
import java.awt.AWTEvent;
import java.awt.Component;
import java.awt.KeyboardFocusManager;
import java.awt.Rectangle;
import java.awt.Toolkit;
import java.awt.event.KeyEvent;
import java.awt.im.InputMethodRequests;
import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.net.StandardProtocolFamily;
import java.net.UnixDomainSocketAddress;
import java.nio.ByteBuffer;
import java.nio.channels.Channels;
import java.nio.channels.SocketChannel;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.time.Instant;
import java.util.concurrent.atomic.AtomicBoolean;

public final class CaretBridge implements AppLifecycleListener {
    private static final AtomicBoolean STARTED = new AtomicBoolean();
    private static final Path HOME = Path.of(System.getProperty("user.home"));
    private static final Path SUPPORT = HOME.resolve("Library/Application Support/TermGuru");
    private static final Path SOCKET = SUPPORT.resolve("run/guru.sock");
    private static final Path DEBUG_FLAG = SUPPORT.resolve("debug-caret");
    private static final Path DEBUG_LOG = HOME.resolve("Library/Logs/TermGuru/jetbrains.log");

    @Override
    public void appStarted() {
        if (!STARTED.compareAndSet(false, true)) return;

        Thread thread = new Thread(CaretBridge::connectLoop, "TermGuru caret bridge");
        thread.setDaemon(true);
        thread.start();

        if (Files.exists(DEBUG_FLAG)) {
            debug("started pid=" + ProcessHandle.current().pid());
            Toolkit.getDefaultToolkit().addAWTEventListener(event -> {
                if (event.getID() != KeyEvent.KEY_TYPED) return;
                // Read after the component handled the key, otherwise the rect lags one event.
                SwingUtilities.invokeLater(() -> debug(caretJson()));
            }, AWTEvent.KEY_EVENT_MASK);
        }
    }

    private static void connectLoop() {
        while (true) {
            try (SocketChannel channel = SocketChannel.open(StandardProtocolFamily.UNIX)) {
                channel.connect(UnixDomainSocketAddress.of(SOCKET));
                send(channel, "{\"t\":\"ide\",\"pid\":" + ProcessHandle.current().pid() + "}");
                BufferedReader reader = new BufferedReader(
                        new InputStreamReader(Channels.newInputStream(channel), StandardCharsets.UTF_8));
                String line;
                while ((line = reader.readLine()) != null) {
                    if (!line.contains("\"caret?\"")) continue;
                    SwingUtilities.invokeLater(() -> {
                        try {
                            send(channel, caretJson());
                        } catch (Exception ignored) {
                        }
                    });
                }
            } catch (Exception ignored) {
            }
            try {
                Thread.sleep(2000);
            } catch (InterruptedException e) {
                return;
            }
        }
    }

    private static synchronized void send(SocketChannel channel, String line) throws Exception {
        ByteBuffer buffer = ByteBuffer.wrap((line + "\n").getBytes(StandardCharsets.UTF_8));
        while (buffer.hasRemaining()) channel.write(buffer);
    }

    /** Rect is in AWT screen coordinates: origin top-left of the primary display. */
    private static String caretJson() {
        long pid = ProcessHandle.current().pid();
        Component focus = KeyboardFocusManager.getCurrentKeyboardFocusManager().getFocusOwner();
        if (focus == null) return "{\"t\":\"caret\",\"pid\":" + pid + ",\"ok\":false}";

        boolean terminal = false;
        for (Component c = focus; c != null; c = c.getParent()) {
            if (c.getClass().getName().toLowerCase().contains("terminal")) {
                terminal = true;
                break;
            }
        }

        Rectangle rect = null;
        try {
            InputMethodRequests requests = focus.getInputMethodRequests();
            if (requests != null) rect = requests.getTextLocation(null);
        } catch (Exception ignored) {
        }
        if (rect == null) {
            return "{\"t\":\"caret\",\"pid\":" + pid + ",\"ok\":false,\"terminal\":" + terminal
                    + ",\"cls\":\"" + focus.getClass().getName() + "\"}";
        }
        return "{\"t\":\"caret\",\"pid\":" + pid + ",\"ok\":true,\"terminal\":" + terminal
                + ",\"x\":" + rect.x + ",\"y\":" + rect.y + ",\"w\":" + rect.width + ",\"h\":" + rect.height
                + ",\"cls\":\"" + focus.getClass().getName() + "\"}";
    }

    private static void debug(String message) {
        try {
            Files.createDirectories(DEBUG_LOG.getParent());
            Files.writeString(DEBUG_LOG, Instant.now() + " " + message + "\n",
                    StandardOpenOption.CREATE, StandardOpenOption.APPEND);
        } catch (Exception ignored) {
        }
    }
}
