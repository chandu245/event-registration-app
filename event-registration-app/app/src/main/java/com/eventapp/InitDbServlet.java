package com.eventapp;

import jakarta.servlet.ServletContextEvent;
import jakarta.servlet.ServletContextListener;
import jakarta.servlet.annotation.WebListener;

import java.sql.Connection;
import java.sql.Statement;

@WebListener
public class InitDbServlet implements ServletContextListener {
    @Override
    public void contextInitialized(ServletContextEvent sce) {
        String createTable = "CREATE TABLE IF NOT EXISTS registrations (" +
                "id INT AUTO_INCREMENT PRIMARY KEY, " +
                "name VARCHAR(100) NOT NULL, " +
                "email VARCHAR(100) NOT NULL, " +
                "contact VARCHAR(20), " +
                "address VARCHAR(255), " +
                "created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)";
        try (Connection conn = DBUtil.getConnection();
             Statement st = conn.createStatement()) {
            st.execute(createTable);
        } catch (Exception e) {
            e.printStackTrace(); // log only — don't crash startup if DB isn't ready yet
        }
    }
}
