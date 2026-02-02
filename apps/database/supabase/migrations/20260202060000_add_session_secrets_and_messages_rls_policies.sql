-- Add INSERT policy for agent_coding_session_secrets
-- Users can insert secrets for sessions they own
CREATE POLICY "Users can insert their own agent coding session secrets"
ON "public"."agent_coding_session_secrets"
FOR INSERT
TO authenticated
WITH CHECK (
    EXISTS (
        SELECT 1 FROM agent_coding_sessions
        WHERE agent_coding_sessions.id = agent_coding_session_secrets.session_id
        AND agent_coding_sessions.user_id = auth.uid()
    )
);

-- Add UPDATE policy for agent_coding_session_secrets
-- Users can update secrets for sessions they own
CREATE POLICY "Users can update their own agent coding session secrets"
ON "public"."agent_coding_session_secrets"
FOR UPDATE
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM agent_coding_sessions
        WHERE agent_coding_sessions.id = agent_coding_session_secrets.session_id
        AND agent_coding_sessions.user_id = auth.uid()
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1 FROM agent_coding_sessions
        WHERE agent_coding_sessions.id = agent_coding_session_secrets.session_id
        AND agent_coding_sessions.user_id = auth.uid()
    )
);

-- Add DELETE policy for agent_coding_session_secrets
-- Users can delete secrets for sessions they own
CREATE POLICY "Users can delete their own agent coding session secrets"
ON "public"."agent_coding_session_secrets"
FOR DELETE
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM agent_coding_sessions
        WHERE agent_coding_sessions.id = agent_coding_session_secrets.session_id
        AND agent_coding_sessions.user_id = auth.uid()
    )
);

-- Add INSERT policy for agent_coding_session_messages
-- Users can insert messages for sessions they own
CREATE POLICY "Users can insert their own agent coding session messages"
ON "public"."agent_coding_session_messages"
FOR INSERT
TO authenticated
WITH CHECK (
    EXISTS (
        SELECT 1 FROM agent_coding_sessions
        WHERE agent_coding_sessions.id = agent_coding_session_messages.session_id
        AND agent_coding_sessions.user_id = auth.uid()
    )
);

-- Add UPDATE policy for agent_coding_session_messages
-- Users can update messages for sessions they own
CREATE POLICY "Users can update their own agent coding session messages"
ON "public"."agent_coding_session_messages"
FOR UPDATE
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM agent_coding_sessions
        WHERE agent_coding_sessions.id = agent_coding_session_messages.session_id
        AND agent_coding_sessions.user_id = auth.uid()
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1 FROM agent_coding_sessions
        WHERE agent_coding_sessions.id = agent_coding_session_messages.session_id
        AND agent_coding_sessions.user_id = auth.uid()
    )
);

-- Add DELETE policy for agent_coding_session_messages
-- Users can delete messages for sessions they own
CREATE POLICY "Users can delete their own agent coding session messages"
ON "public"."agent_coding_session_messages"
FOR DELETE
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM agent_coding_sessions
        WHERE agent_coding_sessions.id = agent_coding_session_messages.session_id
        AND agent_coding_sessions.user_id = auth.uid()
    )
);
