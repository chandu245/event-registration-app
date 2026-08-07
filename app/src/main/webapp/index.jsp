<%@ page contentType="text/html;charset=UTF-8" %>
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Event Registration</title>
  <style>
    /* Reset and Base Styles */
    * {
      box-sizing: border-box;
      margin: 0;
      padding: 0;
      font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
    }

    body {
      min-height: 100vh;
      display: flex;
      justify-content: center;
      align-items: center;
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      padding: 20px;
    }

    /* Glassmorphism Card Container */
    .form-container {
      background: rgba(255, 255, 255, 0.15);
      backdrop-filter: blur(10px);
      -webkit-backdrop-filter: blur(10px);
      border: 1px solid rgba(255, 255, 255, 0.2);
      border-radius: 16px;
      padding: 40px;
      width: 100%;
      max-width: 450px;
      box-shadow: 0 8px 32px 0 rgba(0, 0, 0, 0.3);
    }

    h2 {
      color: #ffffff;
      text-align: center;
      margin-bottom: 30px;
      font-weight: 600;
      letter-spacing: 0.5px;
    }

    /* Form Fields Styling */
    .form-group {
      margin-bottom: 20px;
    }

    label {
      display: block;
      color: rgba(255, 255, 255, 0.9);
      margin-bottom: 8px;
      font-size: 14px;
      font-weight: 500;
    }

    input[type="text"],
    input[type="email"],
    textarea {
      width: 100%;
      padding: 12px 16px;
      background: rgba(255, 255, 255, 0.2);
      border: 1px solid rgba(255, 255, 255, 0.1);
      border-radius: 8px;
      color: #ffffff;
      font-size: 15px;
      outline: none;
      transition: all 0.3s ease;
    }

    /* Interactive States */
    input[type="text"]:focus,
    input[type="email"]:focus,
    textarea:focus {
      background: rgba(255, 255, 255, 0.25);
      border-color: rgba(255, 255, 255, 0.6);
      box-shadow: 0 0 8px rgba(255, 255, 255, 0.2);
    }

    /* Fixed Height for Textarea */
    textarea {
      resize: none;
      height: 100px;
    }

    /* Input Placeholder Color */
    ::placeholder {
      color: rgba(255, 255, 255, 0.6);
    }

    /* Smooth Button Styling */
    input[type="submit"] {
      width: 100%;
      padding: 14px;
      background: #ffffff;
      border: none;
      border-radius: 8px;
      color: #764ba2;
      font-size: 16px;
      font-weight: 600;
      cursor: pointer;
      transition: all 0.3s ease;
      box-shadow: 0 4px 15px rgba(0, 0, 0, 0.1);
      margin-top: 10px;
    }

    input[type="submit"]:hover {
      background: #f0f0f0;
      transform: translateY(-2px);
      box-shadow: 0 6px 20px rgba(0, 0, 0, 0.15);
    }

    input[type="submit"]:active {
      transform: translateY(0);
    }
  </style>
</head>
<body>

  <div class="form-container">
    <h2>Register for the Event</h2>
    
    <form action="register" method="post">
      <div class="form-group">
        <label for="name">Name</label>
        <input type="text" id="name" name="name" placeholder="John Doe" required>
      </div>

      <div class="form-group">
        <label for="email">Email Address</label>
        <input type="email" id="email" name="email" placeholder="john@example.com" required>
      </div>

      <div class="form-group">
        <label for="contact">Contact Number</label>
        <input type="text" id="contact" name="contact" placeholder="+1 234 567 890" required>
      </div>

      <div class="form-group">
        <label for="address">Address</label>
        <textarea id="address" name="address" placeholder="Enter your full street address" required></textarea>
      </div>

      <input type="submit" value="Register Now">
    </form>
  </div>

</body>
</html>
