package com.eventapp;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;

public class DBUtil {

    static {
        // Explicit driver registration. JDBC 4.0+ normally auto-registers drivers via
        // META-INF/services/java.sql.Driver, but forcing it here guards against classloader
        // edge cases (e.g. filters/threads that don't delegate to the webapp classloader)
        // and gives a clear, early error if the driver jar simply isn't on the classpath.
        try {
            Class.forName("com.mysql.cj.jdbc.Driver");
        } catch (ClassNotFoundException e) {
            throw new ExceptionInInitializerError(
                "MySQL JDBC driver not found on classpath. Check that mysql-connector-j " +
                "is in WEB-INF/lib inside the deployed WAR: " + e.getMessage());
        }
    }

    public static Connection getConnection() throws SQLException {
        String url = System.getenv("DB_URL");   // e.g. jdbc:mysql://mysql-service:3306/eventdb
        String user = System.getenv("DB_USER");
        String pass = System.getenv("DB_PASS");
        return DriverManager.getConnection(url, user, pass);
    }
}
