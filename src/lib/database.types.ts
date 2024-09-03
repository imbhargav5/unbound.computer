export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  graphql_public: {
    Tables: {
      [_ in never]: never
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      graphql: {
        Args: {
          operationName?: string
          query?: string
          variables?: Json
          extensions?: Json
        }
        Returns: Json
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
  public: {
    Tables: {
      account_delete_tokens: {
        Row: {
          token: string
          user_id: string
        }
        Insert: {
          token?: string
          user_id: string
        }
        Update: {
          token?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "account_delete_tokens_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      billing_customers: {
        Row: {
          billing_email: string
          default_currency: string | null
          gateway_customer_id: string
          gateway_name: string
          gateway_plan_id: string | null
          metadata: Json | null
          workspace_id: string
        }
        Insert: {
          billing_email: string
          default_currency?: string | null
          gateway_customer_id: string
          gateway_name: string
          gateway_plan_id?: string | null
          metadata?: Json | null
          workspace_id: string
        }
        Update: {
          billing_email?: string
          default_currency?: string | null
          gateway_customer_id?: string
          gateway_name?: string
          gateway_plan_id?: string | null
          metadata?: Json | null
          workspace_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "billing_customers_gateway_plan_id_fkey"
            columns: ["gateway_plan_id"]
            isOneToOne: false
            referencedRelation: "billing_plans"
            referencedColumns: ["gateway_plan_id"]
          },
          {
            foreignKeyName: "billing_customers_workspace_id_fkey"
            columns: ["workspace_id"]
            isOneToOne: false
            referencedRelation: "workspaces"
            referencedColumns: ["id"]
          },
        ]
      }
      billing_invoices: {
        Row: {
          amount: number
          currency: string
          due_date: string
          gateway_customer_id: string
          hosted_invoice_url: string | null
          id: string
          paid_date: string | null
          status: string
        }
        Insert: {
          amount: number
          currency: string
          due_date: string
          gateway_customer_id: string
          hosted_invoice_url?: string | null
          id?: string
          paid_date?: string | null
          status: string
        }
        Update: {
          amount?: number
          currency?: string
          due_date?: string
          gateway_customer_id?: string
          hosted_invoice_url?: string | null
          id?: string
          paid_date?: string | null
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "billing_invoices_gateway_customer_id_fkey"
            columns: ["gateway_customer_id"]
            isOneToOne: false
            referencedRelation: "billing_customers"
            referencedColumns: ["gateway_customer_id"]
          },
        ]
      }
      billing_payments: {
        Row: {
          amount: number
          currency: string
          gateway_customer_id: string
          gateway_name: string
          gateway_payment_id: string
          gateway_plan_id: string | null
          payment_date: string
          status: string
        }
        Insert: {
          amount: number
          currency: string
          gateway_customer_id: string
          gateway_name: string
          gateway_payment_id: string
          gateway_plan_id?: string | null
          payment_date: string
          status: string
        }
        Update: {
          amount?: number
          currency?: string
          gateway_customer_id?: string
          gateway_name?: string
          gateway_payment_id?: string
          gateway_plan_id?: string | null
          payment_date?: string
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "billing_payments_gateway_customer_id_fkey"
            columns: ["gateway_customer_id"]
            isOneToOne: false
            referencedRelation: "billing_customers"
            referencedColumns: ["gateway_customer_id"]
          },
          {
            foreignKeyName: "billing_payments_gateway_plan_id_fkey"
            columns: ["gateway_plan_id"]
            isOneToOne: false
            referencedRelation: "billing_plans"
            referencedColumns: ["gateway_plan_id"]
          },
        ]
      }
      billing_plan_prices: {
        Row: {
          active: boolean
          amount: number
          currency: string
          gateway_plan_id: string
          id: string
          recurring_interval: string
          tier: string | null
        }
        Insert: {
          active?: boolean
          amount: number
          currency: string
          gateway_plan_id: string
          id?: string
          recurring_interval: string
          tier?: string | null
        }
        Update: {
          active?: boolean
          amount?: number
          currency?: string
          gateway_plan_id?: string
          id?: string
          recurring_interval?: string
          tier?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "billing_plan_prices_gateway_plan_id_fkey"
            columns: ["gateway_plan_id"]
            isOneToOne: false
            referencedRelation: "billing_plans"
            referencedColumns: ["gateway_plan_id"]
          },
        ]
      }
      billing_plans: {
        Row: {
          active: boolean
          description: string | null
          features: Json | null
          free_trial_days: number | null
          gateway_name: string
          gateway_plan_id: string
          is_subscription: boolean
          name: string
        }
        Insert: {
          active?: boolean
          description?: string | null
          features?: Json | null
          free_trial_days?: number | null
          gateway_name: string
          gateway_plan_id: string
          is_subscription: boolean
          name: string
        }
        Update: {
          active?: boolean
          description?: string | null
          features?: Json | null
          free_trial_days?: number | null
          gateway_name?: string
          gateway_plan_id?: string
          is_subscription?: boolean
          name?: string
        }
        Relationships: []
      }
      billing_subscriptions: {
        Row: {
          cancel_at_period_end: boolean
          currency: string
          current_period_end: string
          current_period_start: string
          gateway_customer_id: string
          gateway_name: string
          gateway_plan_id: string
          gateway_subscription_id: string
          id: string
          is_trial: boolean
          quantity: number | null
          status: Database["public"]["Enums"]["subscription_status"]
          trial_ends_at: string | null
        }
        Insert: {
          cancel_at_period_end: boolean
          currency: string
          current_period_end: string
          current_period_start: string
          gateway_customer_id: string
          gateway_name: string
          gateway_plan_id: string
          gateway_subscription_id: string
          id?: string
          is_trial: boolean
          quantity?: number | null
          status: Database["public"]["Enums"]["subscription_status"]
          trial_ends_at?: string | null
        }
        Update: {
          cancel_at_period_end?: boolean
          currency?: string
          current_period_end?: string
          current_period_start?: string
          gateway_customer_id?: string
          gateway_name?: string
          gateway_plan_id?: string
          gateway_subscription_id?: string
          id?: string
          is_trial?: boolean
          quantity?: number | null
          status?: Database["public"]["Enums"]["subscription_status"]
          trial_ends_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "billing_subscriptions_gateway_customer_id_fkey"
            columns: ["gateway_customer_id"]
            isOneToOne: false
            referencedRelation: "billing_customers"
            referencedColumns: ["gateway_customer_id"]
          },
        ]
      }
      billing_usage_logs: {
        Row: {
          feature: string
          gateway_customer_id: string
          id: string
          timestamp: string
          usage_amount: number
        }
        Insert: {
          feature: string
          gateway_customer_id: string
          id?: string
          timestamp?: string
          usage_amount: number
        }
        Update: {
          feature?: string
          gateway_customer_id?: string
          id?: string
          timestamp?: string
          usage_amount?: number
        }
        Relationships: [
          {
            foreignKeyName: "billing_usage_logs_gateway_customer_id_fkey"
            columns: ["gateway_customer_id"]
            isOneToOne: false
            referencedRelation: "billing_customers"
            referencedColumns: ["gateway_customer_id"]
          },
        ]
      }
      billing_volume_tiers: {
        Row: {
          id: string
          max_quantity: number | null
          min_quantity: number
          plan_price_id: string
          unit_price: number
        }
        Insert: {
          id?: string
          max_quantity?: number | null
          min_quantity: number
          plan_price_id: string
          unit_price: number
        }
        Update: {
          id?: string
          max_quantity?: number | null
          min_quantity?: number
          plan_price_id?: string
          unit_price?: number
        }
        Relationships: [
          {
            foreignKeyName: "billing_volume_tiers_plan_price_id_fkey"
            columns: ["plan_price_id"]
            isOneToOne: false
            referencedRelation: "billing_plan_prices"
            referencedColumns: ["id"]
          },
        ]
      }
      chats: {
        Row: {
          created_at: string
          id: string
          payload: Json | null
          project_id: string
          user_id: string
        }
        Insert: {
          created_at?: string
          id: string
          payload?: Json | null
          project_id: string
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          payload?: Json | null
          project_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "chats_project_id_fkey"
            columns: ["project_id"]
            isOneToOne: false
            referencedRelation: "projects"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "chats_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      marketing_author_profiles: {
        Row: {
          avatar_url: string
          bio: string
          created_at: string
          display_name: string
          facebook_handle: string | null
          id: string
          instagram_handle: string | null
          linkedin_handle: string | null
          slug: string
          twitter_handle: string | null
          updated_at: string
          website_url: string | null
        }
        Insert: {
          avatar_url: string
          bio: string
          created_at?: string
          display_name: string
          facebook_handle?: string | null
          id?: string
          instagram_handle?: string | null
          linkedin_handle?: string | null
          slug: string
          twitter_handle?: string | null
          updated_at?: string
          website_url?: string | null
        }
        Update: {
          avatar_url?: string
          bio?: string
          created_at?: string
          display_name?: string
          facebook_handle?: string | null
          id?: string
          instagram_handle?: string | null
          linkedin_handle?: string | null
          slug?: string
          twitter_handle?: string | null
          updated_at?: string
          website_url?: string | null
        }
        Relationships: []
      }
      marketing_blog_author_posts: {
        Row: {
          author_id: string
          post_id: string
        }
        Insert: {
          author_id: string
          post_id: string
        }
        Update: {
          author_id?: string
          post_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "marketing_blog_author_posts_author_id_fkey"
            columns: ["author_id"]
            isOneToOne: false
            referencedRelation: "marketing_author_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "marketing_blog_author_posts_post_id_fkey"
            columns: ["post_id"]
            isOneToOne: false
            referencedRelation: "marketing_blog_posts"
            referencedColumns: ["id"]
          },
        ]
      }
      marketing_blog_post_tags_relationship: {
        Row: {
          blog_post_id: string
          tag_id: string
        }
        Insert: {
          blog_post_id: string
          tag_id: string
        }
        Update: {
          blog_post_id?: string
          tag_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "marketing_blog_post_tags_relationship_blog_post_id_fkey"
            columns: ["blog_post_id"]
            isOneToOne: false
            referencedRelation: "marketing_blog_posts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "marketing_blog_post_tags_relationship_tag_id_fkey"
            columns: ["tag_id"]
            isOneToOne: false
            referencedRelation: "marketing_tags"
            referencedColumns: ["id"]
          },
        ]
      }
      marketing_blog_posts: {
        Row: {
          content: string
          cover_image: string | null
          created_at: string
          id: string
          is_featured: boolean
          json_content: Json
          seo_data: Json | null
          slug: string
          status: Database["public"]["Enums"]["marketing_blog_post_status"]
          summary: string
          title: string
          updated_at: string
        }
        Insert: {
          content: string
          cover_image?: string | null
          created_at?: string
          id?: string
          is_featured?: boolean
          json_content?: Json
          seo_data?: Json | null
          slug: string
          status?: Database["public"]["Enums"]["marketing_blog_post_status"]
          summary: string
          title: string
          updated_at?: string
        }
        Update: {
          content?: string
          cover_image?: string | null
          created_at?: string
          id?: string
          is_featured?: boolean
          json_content?: Json
          seo_data?: Json | null
          slug?: string
          status?: Database["public"]["Enums"]["marketing_blog_post_status"]
          summary?: string
          title?: string
          updated_at?: string
        }
        Relationships: []
      }
      marketing_changelog: {
        Row: {
          changes: string
          cover_image: string | null
          created_at: string | null
          id: string
          title: string
          updated_at: string | null
        }
        Insert: {
          changes: string
          cover_image?: string | null
          created_at?: string | null
          id?: string
          title: string
          updated_at?: string | null
        }
        Update: {
          changes?: string
          cover_image?: string | null
          created_at?: string | null
          id?: string
          title?: string
          updated_at?: string | null
        }
        Relationships: []
      }
      marketing_changelog_author_relationship: {
        Row: {
          author_id: string
          changelog_id: string
        }
        Insert: {
          author_id: string
          changelog_id: string
        }
        Update: {
          author_id?: string
          changelog_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "marketing_changelog_author_relationship_author_id_fkey"
            columns: ["author_id"]
            isOneToOne: false
            referencedRelation: "marketing_author_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "marketing_changelog_author_relationship_changelog_id_fkey"
            columns: ["changelog_id"]
            isOneToOne: false
            referencedRelation: "marketing_changelog"
            referencedColumns: ["id"]
          },
        ]
      }
      marketing_feedback_comments: {
        Row: {
          content: string
          created_at: string
          id: string
          thread_id: string
          updated_at: string
          user_id: string
        }
        Insert: {
          content: string
          created_at?: string
          id?: string
          thread_id: string
          updated_at?: string
          user_id: string
        }
        Update: {
          content?: string
          created_at?: string
          id?: string
          thread_id?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "marketing_feedback_comments_thread_id_fkey"
            columns: ["thread_id"]
            isOneToOne: false
            referencedRelation: "marketing_feedback_threads"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "marketing_feedback_comments_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      marketing_feedback_threads: {
        Row: {
          added_to_roadmap: boolean
          content: string
          created_at: string
          id: string
          is_publicly_visible: boolean
          open_for_public_discussion: boolean
          priority: Database["public"]["Enums"]["marketing_feedback_thread_priority"]
          status: Database["public"]["Enums"]["marketing_feedback_thread_status"]
          title: string
          type: Database["public"]["Enums"]["marketing_feedback_thread_type"]
          updated_at: string
          user_id: string
        }
        Insert: {
          added_to_roadmap?: boolean
          content: string
          created_at?: string
          id?: string
          is_publicly_visible?: boolean
          open_for_public_discussion?: boolean
          priority?: Database["public"]["Enums"]["marketing_feedback_thread_priority"]
          status?: Database["public"]["Enums"]["marketing_feedback_thread_status"]
          title: string
          type?: Database["public"]["Enums"]["marketing_feedback_thread_type"]
          updated_at?: string
          user_id: string
        }
        Update: {
          added_to_roadmap?: boolean
          content?: string
          created_at?: string
          id?: string
          is_publicly_visible?: boolean
          open_for_public_discussion?: boolean
          priority?: Database["public"]["Enums"]["marketing_feedback_thread_priority"]
          status?: Database["public"]["Enums"]["marketing_feedback_thread_status"]
          title?: string
          type?: Database["public"]["Enums"]["marketing_feedback_thread_type"]
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "marketing_feedback_threads_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      marketing_tags: {
        Row: {
          description: string | null
          id: string
          name: string
          slug: string
        }
        Insert: {
          description?: string | null
          id?: string
          name: string
          slug: string
        }
        Update: {
          description?: string | null
          id?: string
          name?: string
          slug?: string
        }
        Relationships: []
      }
      project_comments: {
        Row: {
          created_at: string | null
          id: string
          in_reply_to: string | null
          project_id: string
          text: string
          user_id: string
        }
        Insert: {
          created_at?: string | null
          id?: string
          in_reply_to?: string | null
          project_id: string
          text: string
          user_id: string
        }
        Update: {
          created_at?: string | null
          id?: string
          in_reply_to?: string | null
          project_id?: string
          text?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "project_comments_project_id_fkey"
            columns: ["project_id"]
            isOneToOne: false
            referencedRelation: "projects"
            referencedColumns: ["id"]
          },
        ]
      }
      projects: {
        Row: {
          created_at: string
          id: string
          name: string
          project_status: Database["public"]["Enums"]["project_status"]
          slug: string
          updated_at: string
          workspace_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          name: string
          project_status?: Database["public"]["Enums"]["project_status"]
          slug?: string
          updated_at?: string
          workspace_id: string
        }
        Update: {
          created_at?: string
          id?: string
          name?: string
          project_status?: Database["public"]["Enums"]["project_status"]
          slug?: string
          updated_at?: string
          workspace_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "projects_workspace_id_fkey"
            columns: ["workspace_id"]
            isOneToOne: false
            referencedRelation: "workspaces"
            referencedColumns: ["id"]
          },
        ]
      }
      user_api_keys: {
        Row: {
          created_at: string
          expires_at: string | null
          is_revoked: boolean
          key_id: string
          masked_key: string
          user_id: string
        }
        Insert: {
          created_at?: string
          expires_at?: string | null
          is_revoked?: boolean
          key_id: string
          masked_key: string
          user_id: string
        }
        Update: {
          created_at?: string
          expires_at?: string | null
          is_revoked?: boolean
          key_id?: string
          masked_key?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_api_keys_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      user_application_settings: {
        Row: {
          email_readonly: string
          id: string
        }
        Insert: {
          email_readonly: string
          id: string
        }
        Update: {
          email_readonly?: string
          id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_application_settings_id_fkey"
            columns: ["id"]
            isOneToOne: true
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      user_notifications: {
        Row: {
          created_at: string
          id: string
          is_read: boolean
          is_seen: boolean
          payload: Json
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          is_read?: boolean
          is_seen?: boolean
          payload?: Json
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          is_read?: boolean
          is_seen?: boolean
          payload?: Json
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_notifications_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      user_profiles: {
        Row: {
          avatar_url: string | null
          created_at: string
          full_name: string | null
          id: string
        }
        Insert: {
          avatar_url?: string | null
          created_at?: string
          full_name?: string | null
          id: string
        }
        Update: {
          avatar_url?: string | null
          created_at?: string
          full_name?: string | null
          id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_profiles_id_fkey"
            columns: ["id"]
            isOneToOne: true
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      user_roles: {
        Row: {
          id: string
          role: Database["public"]["Enums"]["app_role"]
          user_id: string
        }
        Insert: {
          id?: string
          role: Database["public"]["Enums"]["app_role"]
          user_id: string
        }
        Update: {
          id?: string
          role?: Database["public"]["Enums"]["app_role"]
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_roles_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      user_settings: {
        Row: {
          default_workspace: string | null
          id: string
        }
        Insert: {
          default_workspace?: string | null
          id: string
        }
        Update: {
          default_workspace?: string | null
          id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_settings_default_workspace_fkey"
            columns: ["default_workspace"]
            isOneToOne: false
            referencedRelation: "workspaces"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_settings_id_fkey"
            columns: ["id"]
            isOneToOne: true
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      workspace_admin_settings: {
        Row: {
          workspace_id: string
          workspace_settings: Json
        }
        Insert: {
          workspace_id: string
          workspace_settings?: Json
        }
        Update: {
          workspace_id?: string
          workspace_settings?: Json
        }
        Relationships: [
          {
            foreignKeyName: "workspace_admin_settings_workspace_id_fkey"
            columns: ["workspace_id"]
            isOneToOne: true
            referencedRelation: "workspaces"
            referencedColumns: ["id"]
          },
        ]
      }
      workspace_application_settings: {
        Row: {
          membership_type: Database["public"]["Enums"]["workspace_membership_type"]
          workspace_id: string
        }
        Insert: {
          membership_type?: Database["public"]["Enums"]["workspace_membership_type"]
          workspace_id: string
        }
        Update: {
          membership_type?: Database["public"]["Enums"]["workspace_membership_type"]
          workspace_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "workspace_application_settings_workspace_id_fkey"
            columns: ["workspace_id"]
            isOneToOne: true
            referencedRelation: "workspaces"
            referencedColumns: ["id"]
          },
        ]
      }
      workspace_credits: {
        Row: {
          credits: number
          id: string
          last_reset_date: string | null
          workspace_id: string
        }
        Insert: {
          credits?: number
          id?: string
          last_reset_date?: string | null
          workspace_id: string
        }
        Update: {
          credits?: number
          id?: string
          last_reset_date?: string | null
          workspace_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "workspace_credits_workspace_id_fkey"
            columns: ["workspace_id"]
            isOneToOne: false
            referencedRelation: "workspaces"
            referencedColumns: ["id"]
          },
        ]
      }
      workspace_credits_logs: {
        Row: {
          change_type: string
          changed_at: string
          id: string
          new_credits: number | null
          old_credits: number | null
          workspace_credits_id: string
          workspace_id: string
        }
        Insert: {
          change_type: string
          changed_at?: string
          id?: string
          new_credits?: number | null
          old_credits?: number | null
          workspace_credits_id: string
          workspace_id: string
        }
        Update: {
          change_type?: string
          changed_at?: string
          id?: string
          new_credits?: number | null
          old_credits?: number | null
          workspace_credits_id?: string
          workspace_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "workspace_credits_logs_workspace_credits_id_fkey"
            columns: ["workspace_credits_id"]
            isOneToOne: false
            referencedRelation: "workspace_credits"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "workspace_credits_logs_workspace_id_fkey"
            columns: ["workspace_id"]
            isOneToOne: false
            referencedRelation: "workspaces"
            referencedColumns: ["id"]
          },
        ]
      }
      workspace_invitations: {
        Row: {
          created_at: string
          id: string
          invitee_user_email: string
          invitee_user_id: string | null
          invitee_user_role: Database["public"]["Enums"]["workspace_user_role"]
          inviter_user_id: string
          status: Database["public"]["Enums"]["workspace_invitation_link_status"]
          workspace_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          invitee_user_email: string
          invitee_user_id?: string | null
          invitee_user_role?: Database["public"]["Enums"]["workspace_user_role"]
          inviter_user_id: string
          status?: Database["public"]["Enums"]["workspace_invitation_link_status"]
          workspace_id: string
        }
        Update: {
          created_at?: string
          id?: string
          invitee_user_email?: string
          invitee_user_id?: string | null
          invitee_user_role?: Database["public"]["Enums"]["workspace_user_role"]
          inviter_user_id?: string
          status?: Database["public"]["Enums"]["workspace_invitation_link_status"]
          workspace_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "workspace_invitations_invitee_user_id_fkey"
            columns: ["invitee_user_id"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "workspace_invitations_inviter_user_id_fkey"
            columns: ["inviter_user_id"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "workspace_invitations_workspace_id_fkey"
            columns: ["workspace_id"]
            isOneToOne: false
            referencedRelation: "workspaces"
            referencedColumns: ["id"]
          },
        ]
      }
      workspace_settings: {
        Row: {
          workspace_id: string
          workspace_settings: Json
        }
        Insert: {
          workspace_id: string
          workspace_settings?: Json
        }
        Update: {
          workspace_id?: string
          workspace_settings?: Json
        }
        Relationships: [
          {
            foreignKeyName: "workspace_settings_workspace_id_fkey"
            columns: ["workspace_id"]
            isOneToOne: true
            referencedRelation: "workspaces"
            referencedColumns: ["id"]
          },
        ]
      }
      workspace_team_members: {
        Row: {
          added_at: string
          id: string
          role: Database["public"]["Enums"]["workspace_user_role"]
          user_profile_id: string
          workspace_id: string
        }
        Insert: {
          added_at?: string
          id?: string
          role: Database["public"]["Enums"]["workspace_user_role"]
          user_profile_id: string
          workspace_id: string
        }
        Update: {
          added_at?: string
          id?: string
          role?: Database["public"]["Enums"]["workspace_user_role"]
          user_profile_id?: string
          workspace_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "workspace_team_members_user_profile_id_fkey"
            columns: ["user_profile_id"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "workspace_team_members_workspace_id_fkey"
            columns: ["workspace_id"]
            isOneToOne: false
            referencedRelation: "workspaces"
            referencedColumns: ["id"]
          },
        ]
      }
      workspaces: {
        Row: {
          created_at: string
          id: string
          name: string
          slug: string
        }
        Insert: {
          created_at?: string
          id?: string
          name: string
          slug?: string
        }
        Update: {
          created_at?: string
          id?: string
          name?: string
          slug?: string
        }
        Relationships: []
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      app_admin_get_projects_created_per_month: {
        Args: Record<PropertyKey, never>
        Returns: {
          month: string
          number_of_projects: number
        }[]
      }
      app_admin_get_recent_30_day_signin_count: {
        Args: Record<PropertyKey, never>
        Returns: number
      }
      app_admin_get_total_organization_count: {
        Args: Record<PropertyKey, never>
        Returns: number
      }
      app_admin_get_total_project_count: {
        Args: Record<PropertyKey, never>
        Returns: number
      }
      app_admin_get_total_user_count: {
        Args: Record<PropertyKey, never>
        Returns: number
      }
      app_admin_get_user_id_by_email: {
        Args: {
          emailarg: string
        }
        Returns: string
      }
      app_admin_get_users_created_per_month: {
        Args: Record<PropertyKey, never>
        Returns: {
          month: string
          number_of_users: number
        }[]
      }
      app_admin_get_workspaces_created_per_month: {
        Args: Record<PropertyKey, never>
        Returns: {
          month: string
          number_of_workspaces: number
        }[]
      }
      check_if_authenticated_user_owns_email: {
        Args: {
          email: string
        }
        Returns: boolean
      }
      custom_access_token_hook: {
        Args: {
          event: Json
        }
        Returns: Json
      }
      decrement_credits: {
        Args: {
          org_id: string
          amount: number
        }
        Returns: undefined
      }
      get_customer_workspace_id: {
        Args: {
          customer_id_arg: string
        }
        Returns: string
      }
      get_project_workspace_uuid: {
        Args: {
          project_id: string
        }
        Returns: string
      }
      get_workspace_team_member_admins: {
        Args: {
          workspace_id: string
        }
        Returns: {
          member_id: string
        }[]
      }
      get_workspace_team_member_ids: {
        Args: {
          workspace_id: string
        }
        Returns: {
          member_id: string
        }[]
      }
      is_workspace_admin: {
        Args: {
          user_id: string
          workspace_id: string
        }
        Returns: boolean
      }
      is_workspace_member: {
        Args: {
          user_id: string
          workspace_id: string
        }
        Returns: boolean
      }
      make_user_app_admin: {
        Args: {
          user_id_arg: string
        }
        Returns: undefined
      }
      remove_app_admin_privilege_for_user: {
        Args: {
          user_id_arg: string
        }
        Returns: undefined
      }
    }
    Enums: {
      app_admin_role: "moderator" | "admin" | "super_admin"
      app_role: "admin"
      marketing_blog_post_status: "draft" | "published"
      marketing_feedback_thread_priority: "low" | "medium" | "high"
      marketing_feedback_thread_status:
        | "open"
        | "under_review"
        | "planned"
        | "closed"
        | "in_progress"
        | "completed"
      marketing_feedback_thread_type: "bug" | "feature_request" | "general"
      organization_joining_status:
        | "invited"
        | "joinied"
        | "declined_invitation"
        | "joined"
      organization_member_role: "owner" | "admin" | "member" | "readonly"
      pricing_plan_interval: "day" | "week" | "month" | "year"
      pricing_type: "one_time" | "recurring"
      project_status: "draft" | "pending_approval" | "approved" | "completed"
      project_team_member_role: "admin" | "member" | "readonly"
      subscription_status:
        | "trialing"
        | "active"
        | "canceled"
        | "incomplete"
        | "incomplete_expired"
        | "past_due"
        | "unpaid"
        | "paused"
      workspace_invitation_link_status:
        | "active"
        | "finished_accepted"
        | "finished_declined"
        | "inactive"
      workspace_membership_type: "solo" | "team"
      workspace_user_role: "owner" | "admin" | "member" | "readonly"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type PublicSchema = Database[Extract<keyof Database, "public">]

export type Tables<
  PublicTableNameOrOptions extends
    | keyof (PublicSchema["Tables"] & PublicSchema["Views"])
    | { schema: keyof Database },
  TableName extends PublicTableNameOrOptions extends { schema: keyof Database }
    ? keyof (Database[PublicTableNameOrOptions["schema"]]["Tables"] &
        Database[PublicTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = PublicTableNameOrOptions extends { schema: keyof Database }
  ? (Database[PublicTableNameOrOptions["schema"]]["Tables"] &
      Database[PublicTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : PublicTableNameOrOptions extends keyof (PublicSchema["Tables"] &
        PublicSchema["Views"])
    ? (PublicSchema["Tables"] &
        PublicSchema["Views"])[PublicTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  PublicTableNameOrOptions extends
    | keyof PublicSchema["Tables"]
    | { schema: keyof Database },
  TableName extends PublicTableNameOrOptions extends { schema: keyof Database }
    ? keyof Database[PublicTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = PublicTableNameOrOptions extends { schema: keyof Database }
  ? Database[PublicTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : PublicTableNameOrOptions extends keyof PublicSchema["Tables"]
    ? PublicSchema["Tables"][PublicTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  PublicTableNameOrOptions extends
    | keyof PublicSchema["Tables"]
    | { schema: keyof Database },
  TableName extends PublicTableNameOrOptions extends { schema: keyof Database }
    ? keyof Database[PublicTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = PublicTableNameOrOptions extends { schema: keyof Database }
  ? Database[PublicTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : PublicTableNameOrOptions extends keyof PublicSchema["Tables"]
    ? PublicSchema["Tables"][PublicTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  PublicEnumNameOrOptions extends
    | keyof PublicSchema["Enums"]
    | { schema: keyof Database },
  EnumName extends PublicEnumNameOrOptions extends { schema: keyof Database }
    ? keyof Database[PublicEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = PublicEnumNameOrOptions extends { schema: keyof Database }
  ? Database[PublicEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : PublicEnumNameOrOptions extends keyof PublicSchema["Enums"]
    ? PublicSchema["Enums"][PublicEnumNameOrOptions]
    : never

