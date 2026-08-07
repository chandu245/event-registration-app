<%@ page contentType="text/html;charset=UTF-8" %>
<!DOCTYPE html>
<html>
<head><title>Event Registration</title></head>
<body>
  <h2>Register for the Event</h2>
  <form action="register" method="post">
    <label>Name:</label><br>
    <input type="text" name="name" required><br><br>

    <label>Email:</label><br>
    <input type="email" name="email" required><br><br>

    <label>Contact Number:</label><br>
    <input type="text" name="contact" required><br><br>

    <label>Address:</label><br>
    <textarea name="address" required></textarea><br><br>

    <input type="submit" value="Register">
  </form>
</body>
</html>
