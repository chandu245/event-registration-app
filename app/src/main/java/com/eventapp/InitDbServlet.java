package com.eventapp;

import jakarta.servlet.ServletContextEvent;
import jakarta.servlet.ServletContextListener;
import jakarta.servlet.annotation.WebListener;

import java.sql.Connection;
import java.sql.Statement;

@WebListener
public class InitDbServlet implements ServletContextListener {

    private static final int MAX_ATTEMPTS = 10;
    private static final long RETRY_DELAY_MS = 5_000; // 5 seconds between retries

    @Override
    public void contextInitialized(ServletContextEvent sce) {
        String createTable =
            "CREATE TABLE IF NOT EXISTS registrations (" +
            "id         INT AUTO_INCREMENT PRIMARY KEY, " +
            "name       VARCHAR(100) NOT NULL, " +
            "email      VARCHAR(100) NOT NULL, " +
            "contact    VARCHAR(20), " +
            "address    VARCHAR(255), " +
            "created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)";

        // Retry with back-off to survive the MySQL startup window.
        // The K8s readiness probe ensures MySQL accepts connections before the
        // pod is marked Ready, but the StatefulSet may still be initializing
        // when Tomcat starts (e.g., on a rolling restart). Retrying here gives
        // a second layer of protection so the table is always created.
        for (int attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
            try (Connection conn = DBUtil.getConnection();
                 Statement st = conn.createStatement()) {

                st.execute(createTable);
                System.out.println("[InitDb] registrations table ensured (attempt " + attempt + ")");
                return; // success — exit the retry loop

            } catch (Exception e) {
                System.err.println("[InitDb] Attempt " + attempt + "/" + MAX_ATTEMPTS +
                    " failed: " + e.getMessage());

                if (attempt == MAX_ATTEMPTS) {
                    // Log clearly but don't crash Tomcat startup — the app will
                    // surface a proper SQL error on the first registration attempt,
                    // which is easier to debug than a failed context initialization.
                    System.err.println("[InitDb] WARNING: Could not create registrations table " +
                        "after " + MAX_ATTEMPTS + " attempts. Check DB connectivity.");
                    return;
                }

                try {
                    Thread.sleep(RETRY_DELAY_MS);
                } catch (InterruptedException ie) {
                    Thread.currentThread().interrupt();
                    return;
                }
            }
        }
    }
}
