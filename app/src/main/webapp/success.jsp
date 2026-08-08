<%@ page contentType="text/html;charset=UTF-8" %>
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Registration Successful</title>
  <style>
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

    .card {
      background: rgba(255, 255, 255, 0.15);
      backdrop-filter: blur(10px);
      -webkit-backdrop-filter: blur(10px);
      border: 1px solid rgba(255, 255, 255, 0.2);
      border-radius: 16px;
      padding: 50px 40px;
      width: 100%;
      max-width: 460px;
      box-shadow: 0 8px 32px 0 rgba(0, 0, 0, 0.3);
      text-align: center;
    }

    /* Animated checkmark circle */
    .checkmark-wrapper {
      width: 80px;
      height: 80px;
      background: rgba(255, 255, 255, 0.2);
      border-radius: 50%;
      display: flex;
      align-items: center;
      justify-content: center;
      margin: 0 auto 28px;
      animation: pop 0.4s ease-out forwards;
    }

    @keyframes pop {
      0%   { transform: scale(0.5); opacity: 0; }
      70%  { transform: scale(1.1); }
      100% { transform: scale(1);   opacity: 1; }
    }

    .checkmark {
      font-size: 40px;
      line-height: 1;
    }

    h2 {
      color: #ffffff;
      font-size: 24px;
      font-weight: 700;
      margin-bottom: 12px;
      letter-spacing: 0.3px;
    }

    p {
      color: rgba(255, 255, 255, 0.85);
      font-size: 15px;
      line-height: 1.6;
      margin-bottom: 32px;
    }

    .divider {
      width: 50px;
      height: 2px;
      background: rgba(255, 255, 255, 0.4);
      border-radius: 2px;
      margin: 0 auto 28px;
    }

    .btn {
      display: inline-block;
      padding: 14px 32px;
      background: #ffffff;
      border-radius: 8px;
      color: #764ba2;
      font-size: 15px;
      font-weight: 600;
      text-decoration: none;
      transition: all 0.3s ease;
      box-shadow: 0 4px 15px rgba(0, 0, 0, 0.1);
    }

    .btn:hover {
      background: #f0f0f0;
      transform: translateY(-2px);
      box-shadow: 0 6px 20px rgba(0, 0, 0, 0.15);
    }

    .btn:active {
      transform: translateY(0);
    }

    .footer-note {
      margin-top: 28px;
      font-size: 12px;
      color: rgba(255, 255, 255, 0.55);
    }
  </style>
</head>
<body>

  <div class="card">
    <div class="checkmark-wrapper">
      <span class="checkmark">✓</span>
    </div>

    <h2>You're registered!</h2>
    <p>Thank you — your registration has been confirmed.<br>We look forward to seeing you at the event.</p>

    <div class="divider"></div>

    <a class="btn" href="index.jsp">Register another attendee</a>

    <p class="footer-note">Your details have been recorded in our database.</p>
  </div>

</body>
</html>
