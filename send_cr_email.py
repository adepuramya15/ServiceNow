import smtplib
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
import sys

# Get input from bash script
cr_number = sys.argv[1] if len(sys.argv) > 1 else "UNKNOWN"
reason = sys.argv[2] if len(sys.argv) > 2 else "No reason provided"

# Email setup
sender_email = "yaswanthkumarch2001@gmail.com"
receiver_email = "ramya@middlewaretalents.com"
app_password = "uqjc bszf djfw bsor"  # Generate this via Gmail App Passwords

msg = MIMEMultipart("alternative")
msg["Subject"] = f"Change Request {cr_number} Notification"
msg["From"] = "ServiceNow Automation <{}>".format(sender_email)
msg["To"] = receiver_email

# HTML email content
html = f"""
<html>
  <body style="font-family: Arial, sans-serif; background-color: #f9f9f9; padding: 20px;">
    <div style="background-color: #fff; padding: 20px; border-radius: 10px;">
      <h2 style="color: #0078D7;">🔔 New Change Request Raised</h2>
      <p><strong>Change Request Number:</strong> <span style="color: #333;">{cr_number}</span></p>
      <p><strong>Description:</strong> {reason}</p>
      <p><strong>Submitted By:</strong> Harness CI Pipeline</p>
      <br>
      <a href="https://dev299595.service-now.com/nav_to.do?uri=change_request.do?sysparm_query=number={cr_number}" 
         style="display: inline-block; padding: 10px 20px; background-color: #28a745; color: white; 
                text-decoration: none; border-radius: 5px; font-weight: bold;">
        🔍 View Change Request
      </a>
      <p style="margin-top: 30px;">Thank you,<br>ServiceNow Automation Bot</p>
    </div>
  </body>
</html>
"""

msg.attach(MIMEText(html, "html"))

# Send email using Gmail SMTP
try:
    with smtplib.SMTP("smtp.gmail.com", 587) as server:
        server.starttls()
        server.login(sender_email, app_password)
        server.sendmail(sender_email, receiver_email, msg.as_string())
        print("✅ Email notification sent successfully.")
except Exception as e:
    print(f"❌ Failed to send email: {e}")
