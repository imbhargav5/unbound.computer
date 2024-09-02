/*
 _____ _    _ _____          ____           _____ ______
 /  ___| |  | |  _  |   ___  |  _ \   ___   /  ___| ____
 \ `--.| |  | | |_| |  ( _ ) | |_) | ( _ )  \ `--.| ____|
 `--. \ |  | \____ |  / _ \/\  _ <  / _ \/\ `--. |  __|
 /\__/ / |__| .___/ | | (_>  < |_) || (_>  </\__/ / |____
 \____/ \____/\____/   \___/\/____/  \___/\/\____/\______|
 
 *************************************************************
 *                                                           *
 *                  SUPABASE SETTINGS FILE                   *
 *                                                           *
 * This file contains the initial setup and configuration    *
 * for the Supabase project. It includes various database    *
 * extensions and schema settings necessary for the proper   *
 * functioning of Supabase features.                         *
 *                                                           *
 * Please be cautious when modifying this file, as it may    *
 * affect the core functionality of your Supabase project.   *
 *                                                           *
 *************************************************************
 */
SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = ON;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

CREATE EXTENSION IF NOT EXISTS "pg_net" WITH SCHEMA "extensions";

CREATE EXTENSION IF NOT EXISTS "pgsodium" WITH SCHEMA "pgsodium";

COMMENT ON SCHEMA "public" IS 'standard public schema';

CREATE EXTENSION IF NOT EXISTS "pg_graphql" WITH SCHEMA "graphql";

CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";

CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";

CREATE EXTENSION IF NOT EXISTS "pgjwt" WITH SCHEMA "extensions";

CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";

GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";
GRANT USAGE ON SCHEMA "public" TO "supabase_auth_admin";