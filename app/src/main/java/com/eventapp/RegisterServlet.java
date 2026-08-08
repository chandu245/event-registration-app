package com.eventapp;

import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

import java.io.IOException;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.SQLException;

@WebServlet("/register")
public class RegisterServlet extends HttpServlet {

    protected void doPost(HttpServletRequest req, HttpServletResponse resp)
            throws ServletException, IOException {

        String name    = req.getParameter("name");
        String email   = req.getParameter("email");
        String contact = req.getParameter("contact");
        String address = req.getParameter("address");

        // Validate required fields before hitting the database.
        // req.getParameter() returns null for absent params and "" for blank ones.
        if (isBlank(name) || isBlank(email)) {
            resp.sendError(HttpServletResponse.SC_BAD_REQUEST,
                "Name and email are required fields.");
            return;
        }

        // Basic email format sanity check (server-side mirror of the HTML `type=email`)
        if (!email.contains("@") || !email.contains(".")) {
            resp.sendError(HttpServletResponse.SC_BAD_REQUEST,
                "Please provide a valid email address.");
            return;
        }

        String sql = "INSERT INTO registrations (name, email, contact, address) VALUES (?, ?, ?, ?)";

        try (Connection conn = DBUtil.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {

            ps.setString(1, name.trim());
            ps.setString(2, email.trim());
            ps.setString(3, contact != null ? contact.trim() : null);
            ps.setString(4, address != null ? address.trim() : null);
            ps.executeUpdate();

            resp.sendRedirect("success.jsp");

        } catch (SQLException e) {
            throw new ServletException("Registration failed — database error", e);
        }
    }

    private static boolean isBlank(String s) {
        return s == null || s.trim().isEmpty();
    }
}
