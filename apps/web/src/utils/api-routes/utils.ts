// import sendgrid from '@sendgrid/mail';
import { Resend } from "resend";
import { errors } from "../errors";
import { sendEmailMailpit } from "../send-email-mailpit";

type EmailOptions = {
  to: string;
  from: string;
  subject: string;
  html: string;
};

const shouldUseLocalEmail =
  process.env.NODE_ENV === "development" ||
  process.env.NODE_ENV === "test" ||
  process.env.USE_LOCAL_EMAIL === "true";

export async function sendEmail(options: EmailOptions) {
  if (shouldUseLocalEmail) {
    await sendEmailMailpit(options);
    return;
  }

  try {
    const resend = new Resend(process.env.RESEND_API_KEY);
    // return sendgrid.send(options);
    return resend.emails.send(options);
  } catch (error) {
    errors.add(error);
  }
}
