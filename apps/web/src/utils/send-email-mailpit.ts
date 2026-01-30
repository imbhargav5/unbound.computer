type EmailOptions = {
  to: string;
  from: string;
  subject: string;
  html: string;
};

export async function sendEmailMailpit({
  from,
  to,
  subject,
  html,
}: EmailOptions) {
  const response = await fetch("http://localhost:54324/api/v1/send", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      From: { Email: from },
      To: [{ Email: to }],
      Subject: subject,
      HTML: html,
    }),
  });

  if (!response.ok) {
    const error = await response.text();
    throw new Error(`sendEmailMailpit failed: ${error}`);
  }
}
