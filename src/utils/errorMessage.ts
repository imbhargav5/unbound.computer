import { AuthError } from "@supabase/supabase-js";

type AuthFormErrorReturnType = {
  field?: 'email' | 'password' | 'username'
  message: string;
}

export function handleSupabaseAuthEmailPasswordFormErrors(error: AuthError): AuthFormErrorReturnType {
  switch (error.code) {
    case 'invalid_credentials':
      return { message: 'Invalid email or password. Please try again.' };
    case 'user_not_found':
      return { field: 'email', message: 'User not found. Please check your email or sign up.' };
    case 'email_not_confirmed':
      return { field: 'email', message: 'Please confirm your email address before signing in.' };
    case 'user_already_registered':
      return { field: 'email', message: 'This email is already registered. Please use a different email or try signing in.' };
    case 'signup_disabled':
      return { message: 'Sign-ups are currently disabled. Please contact support for assistance.' };
    case 'weak_password':
      return { field: 'password', message: 'Password is too weak. Please use a stronger password.' };
    case 'email_address_not_authorized':
      return { field: 'email', message: 'This email address is not authorized. Please use a different email or contact support.' };
    case 'too_many_requests':
      return { message: 'Too many attempts. Please try again later.' };
    default:
      console.error('Unhandled Supabase auth error:', error);
      return { message: 'An unexpected error occurred. Please try again or contact support.' };
  }
}

export function handleSupabaseAuthSignUpErrors(error: AuthError): AuthFormErrorReturnType {
  switch (error.code) {
    case 'user_already_exists':
      return { field: 'email', message: 'This email is already registered. Please use a different email or try signing in.' };
    case 'email_signup_disabled':
      return { message: 'Email sign-ups are currently disabled. Please use another method or contact support.' };
    case 'password_too_short':
      return { field: 'password', message: 'Password is too short. Please use a password with at least 6 characters.' };
    case 'email_invalid':
      return { field: 'email', message: 'Invalid email address. Please enter a valid email.' };
    case 'username_taken':
      return { field: 'username', message: 'This username is already taken. Please choose a different username.' };
    default:
      return handleSupabaseAuthEmailPasswordFormErrors(error);
  }
}

export function handleSupabaseAuthPasswordResetErrors(error: AuthError): AuthFormErrorReturnType {
  switch (error.code) {
    case 'user_not_found':
      return { field: 'email', message: 'No account found with this email address.' };
    case 'reset_password_invalid_token':
      return { message: 'Invalid or expired password reset token. Please request a new password reset.' };
    case 'too_many_password_resets':
      return { message: 'Too many password reset attempts. Please try again later.' };
    default:
      return handleSupabaseAuthEmailPasswordFormErrors(error);
  }
}

export function handleSupabaseAuthGeneralErrors(error: AuthError): AuthFormErrorReturnType {
  switch (error.code) {
    case 'auth_session_missing':
      return { message: 'Authentication session is missing. Please sign in again.' };
    case 'auth_invalid_token':
      return { message: 'Invalid authentication token. Please sign in again.' };
    case 'auth_invalid_refresh_token':
      return { message: 'Invalid refresh token. Please sign in again.' };
    case 'auth_api_error':
      return { message: 'Authentication service error. Please try again later.' };
    case 'auth_invalid_credentials':
      return { message: 'Invalid credentials. Please check your email and password.' };
    case 'auth_mfa_required':
      return { message: 'Multi-factor authentication is required. Please complete the MFA process.' };
    default:
      console.error('Unhandled Supabase general auth error:', error);
      return { message: 'An unexpected authentication error occurred. Please try again or contact support.' };
  }
}

export function handleSupabaseAuthSignInErrors(error: AuthError): AuthFormErrorReturnType {
  switch (error.code) {
    case 'invalid_credentials':
      return { message: 'Invalid email or password. Please try again.' };
    case 'user_not_found':
      return { field: 'email', message: 'User not found. Please check your email or sign up.' };
    case 'email_not_confirmed':
      return { field: 'email', message: 'Please confirm your email address before signing in.' };
    case 'invalid_login_credentials':
      return { message: 'Invalid login credentials. Please check your email and password.' };
    case 'too_many_attempts':
      return { message: 'Too many sign-in attempts. Please try again later.' };
    default:
      return handleSupabaseAuthEmailPasswordFormErrors(error);
  }
}

export function handleSupabaseAuthMagicLinkErrors(error: AuthError): AuthFormErrorReturnType {
  switch (error.code) {
    case 'user_not_found':
      return { field: 'email', message: 'No account found with this email address. Please sign up first.' };
    case 'too_many_attempts':
      return { message: 'Too many magic link requests. Please try again later.' };
    case 'email_not_confirmed':
      return { field: 'email', message: 'Please confirm your email address before requesting a magic link.' };
    case 'invalid_email':
      return { field: 'email', message: 'Invalid email address. Please enter a valid email.' };
    default:
      return handleSupabaseAuthGeneralErrors(error);
  }
}

export function handleSupabaseAuthResetPasswordErrors(error: AuthError): AuthFormErrorReturnType {
  switch (error.code) {
    case 'user_not_found':
      return { field: 'email', message: 'No account found with this email address.' };
    case 'reset_password_invalid_token':
      return { message: 'Invalid or expired password reset token. Please request a new password reset.' };
    case 'too_many_password_resets':
      return { message: 'Too many password reset attempts. Please try again later.' };
    case 'invalid_email':
      return { field: 'email', message: 'Invalid email address. Please enter a valid email.' };
    default:
      return handleSupabaseAuthGeneralErrors(error);
  }
}
