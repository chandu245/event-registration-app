package com.eventapp;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;
import java.util.Objects;

public class DBUtil {

    static {
        // Explicit driver registration. JDBC 4.0+ normally auto-registers drivers via
        // META-INF/services/java.sql.Driver, but forcing it here guards against classloader
        // edge cases and gives a clear, early error if the driver jar is missing.
        try {
            Class.forName("com.mysql.cj.jdbc.Driver");
        } catch (ClassNotFoundException e) {
            throw new ExceptionInInitializerError(
                "MySQL JDBC driver not found on classpath. Check that mysql-connector-j " +
                "is in WEB-INF/lib inside the deployed WAR: " + e.getMessage());
        }
    }

    public static Connection getConnection() throws SQLException {
        // Fail with a clear message rather than a NullPointerException if the
        // K8s Secret (db-secret) was not mounted correctly into the pod.
        String url  = Objects.requireNonNull(System.getenv("DB_URL"),
            "DB_URL env var is not set — ensure the 'db-secret' K8s Secret is mounted via envFrom");
        String user = Objects.requireNonNull(System.getenv("DB_USER"),
            "DB_USER env var is not set — ensure the 'db-secret' K8s Secret is mounted via envFrom");
        String pass = Objects.requireNonNull(System.getenv("DB_PASS"),
            "DB_PASS env var is not set — ensure the 'db-secret' K8s Secret is mounted via envFrom");

        return DriverManager.getConnection(url, user, pass);
    }
}
