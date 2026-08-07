package com.eventapp;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;

public class DBUtil {
    public static Connection getConnection() throws SQLException {
        String url = System.getenv("DB_URL");   // e.g. jdbc:mysql://mysql-service:3306/eventdb
        String user = System.getenv("DB_USER");
        String pass = System.getenv("DB_PASS");
        return DriverManager.getConnection(url, user, pass);
    }
}
