import { z } from "zod";

/**
 * Attachments
:
0
Bcc
:
[]
Cc
:
[]
Created
:
"2025-04-14T12:51:38.714Z"
From
:
{Name: "Admin", Address: "admin@email.com"}
ID
:
"WugsugsU7gv88xSsehVQve"
MessageID
:
"e6kbWiaXxtZLWojKQYpwqn@mailpit"
Read
:
false
ReplyTo
:
[]
Size
:
915
Snippet
:
"Confirm your email Follow this link to confirm your email: Confirm your email address Alternatively, enter the code: 763393"
Subject
:
"Confirm Your Email"
Tags
:
[]
To
:
[{Name: "", Address: "peterparker4782@myapp.com"}]
 */
export const inbucketEmailMessageSchema = z.object({
  Created: z.string(),
  From: z.object({
    Name: z.string(),
    Address: z.string(),
  }),
  ID: z.string(),
  MessageID: z.string(),
  Read: z.boolean(),
  Size: z.number(),
  Snippet: z.string(),
  Subject: z.string(),
  To: z.array(
    z.object({
      Name: z.string(),
      Address: z.string(),
    }),
  ),
});

export const inbucketEmailMessagesSchema = z.array(inbucketEmailMessageSchema);

export const inbucketEmailSchema = z
  .object({
    messages: inbucketEmailMessagesSchema,
  })
  .passthrough();

/**
   * message detail schema
   *
   * Attachments
:
[]
Bcc
:
[]
Cc
:
[]
Date
:
"2025-04-14T12:51:38Z"
From
:
{Name: "Admin", Address: "admin@email.com"}
HTML
:
"<h2>Confirm your email</h2>\r\n\r\n<p>Follow this link to confirm your email:</p>\r\n<p><a href=\"http://127.0.0.1:54321/auth/v1/verify?token=pkce_61a64edfd66d6a60cb4094c7cae577f8093784fde7019ccfd6adedf1&amp;type=signup&amp;redirect_to=http://localhost:3000/auth/callback\">Confirm your email address</a></p>\r\n<p>Alternatively, enter the code: 763393</p>\r\n"
ID
:
"WugsugsU7gv88xSsehVQve"
Inline
:
[]
ListUnsubscribe
:
{Header: "", Links: [], Errors: "", HeaderPost: ""}
MessageID
:
"e6kbWiaXxtZLWojKQYpwqn@mailpit"
ReplyTo
:
[]
ReturnPath
:
"admin@email.com"
Size
:
915
Subject
:
"Confirm Your Email"
Tags
:
[]
Text
:
"------------------\nConfirm your email\n------------------\n\nFollow this link to confirm your email:\n\nConfirm your email address ( http://127.0.0.1:54321/auth/v1/verify?token=pkce_61a64edfd66d6a60cb4094c7cae577f8093784fde7019ccfd6adedf1&type=signup&redirect_to=http://localhost:3000/auth/callback )\n\nAlternatively, enter the code: 763393"
To
:
[{Name: "", Address: "peterparker4782@myapp.com"}]
   */

export const inbucketEmailMessageDetailSchema = z
  .object({
    Bcc: z.array(z.string()),
    Cc: z.array(z.string()),
    Date: z.string(),
    From: z.object({
      Name: z.string(),
      Address: z.string(),
    }),
    HTML: z.string(),
    ID: z.string(),
    Inline: z.array(z.string()),
    Size: z.number(),
    Subject: z.string(),
    Text: z.string(),
    To: z.array(
      z.object({
        Name: z.string(),
        Address: z.string(),
      }),
    ),
  })
  .passthrough();
