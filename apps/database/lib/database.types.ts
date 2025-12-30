export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[];

export type Database = {
  graphql_public: {
    Tables: {
      [_ in never]: never;
    };
    Views: {
      [_ in never]: never;
    };
    Functions: {
      graphql: {
        Args: {
          extensions?: Json;
          operationName?: string;
          query?: string;
          variables?: Json;
        };
        Returns: Json;
      };
    };
    Enums: {
      [_ in never]: never;
    };
    CompositeTypes: {
      [_ in never]: never;
    };
  };
  pgbouncer: {
    Tables: {
      [_ in never]: never;
    };
    Views: {
      [_ in never]: never;
    };
    Functions: {
      get_auth: {
        Args: { p_usename: string };
        Returns: {
          password: string;
          username: string;
        }[];
      };
    };
    Enums: {
      [_ in never]: never;
    };
    CompositeTypes: {
      [_ in never]: never;
    };
  };
  public: {
    Tables: {
      account_delete_tokens: {
        Row: {
          token: string;
          user_id: string;
        };
        Insert: {
          token?: string;
          user_id: string;
        };
        Update: {
          token?: string;
          user_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "account_delete_tokens_user_id_fkey";
            columns: ["user_id"];
            referencedRelation: "user_profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      app_settings: {
        Row: {
          id: boolean;
          settings: Json;
          updated_at: string;
        };
        Insert: {
          id?: boolean;
          settings?: Json;
          updated_at?: string;
        };
        Update: {
          id?: boolean;
          settings?: Json;
          updated_at?: string;
        };
        Relationships: [];
      };
      billing_customers: {
        Row: {
          billing_email: string;
          default_currency: string | null;
          gateway_customer_id: string;
          gateway_name: string;
          metadata: Json | null;
          workspace_id: string;
        };
        Insert: {
          billing_email: string;
          default_currency?: string | null;
          gateway_customer_id: string;
          gateway_name: string;
          metadata?: Json | null;
          workspace_id: string;
        };
        Update: {
          billing_email?: string;
          default_currency?: string | null;
          gateway_customer_id?: string;
          gateway_name?: string;
          metadata?: Json | null;
          workspace_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "billing_customers_workspace_id_fkey";
            columns: ["workspace_id"];
            referencedRelation: "workspaces";
            referencedColumns: ["id"];
          },
        ];
      };
      billing_invoices: {
        Row: {
          amount: number;
          currency: string;
          due_date: string | null;
          gateway_customer_id: string;
          gateway_invoice_id: string;
          gateway_name: string;
          gateway_price_id: string | null;
          gateway_product_id: string | null;
          hosted_invoice_url: string | null;
          paid_date: string | null;
          status: string;
        };
        Insert: {
          amount: number;
          currency: string;
          due_date?: string | null;
          gateway_customer_id: string;
          gateway_invoice_id: string;
          gateway_name: string;
          gateway_price_id?: string | null;
          gateway_product_id?: string | null;
          hosted_invoice_url?: string | null;
          paid_date?: string | null;
          status: string;
        };
        Update: {
          amount?: number;
          currency?: string;
          due_date?: string | null;
          gateway_customer_id?: string;
          gateway_invoice_id?: string;
          gateway_name?: string;
          gateway_price_id?: string | null;
          gateway_product_id?: string | null;
          hosted_invoice_url?: string | null;
          paid_date?: string | null;
          status?: string;
        };
        Relationships: [
          {
            foreignKeyName: "billing_invoices_gateway_customer_id_fkey";
            columns: ["gateway_customer_id"];
            referencedRelation: "billing_customers";
            referencedColumns: ["gateway_customer_id"];
          },
          {
            foreignKeyName: "billing_invoices_gateway_price_id_fkey";
            columns: ["gateway_price_id"];
            referencedRelation: "billing_prices";
            referencedColumns: ["gateway_price_id"];
          },
          {
            foreignKeyName: "billing_invoices_gateway_product_id_fkey";
            columns: ["gateway_product_id"];
            referencedRelation: "billing_products";
            referencedColumns: ["gateway_product_id"];
          },
        ];
      };
      billing_one_time_payments: {
        Row: {
          amount: number;
          charge_date: string;
          currency: string;
          gateway_charge_id: string;
          gateway_customer_id: string;
          gateway_invoice_id: string;
          gateway_name: string;
          gateway_price_id: string;
          gateway_product_id: string;
          status: string;
        };
        Insert: {
          amount: number;
          charge_date: string;
          currency: string;
          gateway_charge_id: string;
          gateway_customer_id: string;
          gateway_invoice_id: string;
          gateway_name: string;
          gateway_price_id: string;
          gateway_product_id: string;
          status: string;
        };
        Update: {
          amount?: number;
          charge_date?: string;
          currency?: string;
          gateway_charge_id?: string;
          gateway_customer_id?: string;
          gateway_invoice_id?: string;
          gateway_name?: string;
          gateway_price_id?: string;
          gateway_product_id?: string;
          status?: string;
        };
        Relationships: [
          {
            foreignKeyName: "billing_one_time_payments_gateway_customer_id_fkey";
            columns: ["gateway_customer_id"];
            referencedRelation: "billing_customers";
            referencedColumns: ["gateway_customer_id"];
          },
          {
            foreignKeyName: "billing_one_time_payments_gateway_invoice_id_fkey";
            columns: ["gateway_invoice_id"];
            referencedRelation: "billing_invoices";
            referencedColumns: ["gateway_invoice_id"];
          },
          {
            foreignKeyName: "billing_one_time_payments_gateway_price_id_fkey";
            columns: ["gateway_price_id"];
            referencedRelation: "billing_prices";
            referencedColumns: ["gateway_price_id"];
          },
          {
            foreignKeyName: "billing_one_time_payments_gateway_product_id_fkey";
            columns: ["gateway_product_id"];
            referencedRelation: "billing_products";
            referencedColumns: ["gateway_product_id"];
          },
        ];
      };
      billing_payment_methods: {
        Row: {
          gateway_customer_id: string;
          id: string;
          is_default: boolean;
          payment_method_details: Json;
          payment_method_id: string;
          payment_method_type: string;
        };
        Insert: {
          gateway_customer_id: string;
          id?: string;
          is_default?: boolean;
          payment_method_details: Json;
          payment_method_id: string;
          payment_method_type: string;
        };
        Update: {
          gateway_customer_id?: string;
          id?: string;
          is_default?: boolean;
          payment_method_details?: Json;
          payment_method_id?: string;
          payment_method_type?: string;
        };
        Relationships: [
          {
            foreignKeyName: "billing_payment_methods_gateway_customer_id_fkey";
            columns: ["gateway_customer_id"];
            referencedRelation: "billing_customers";
            referencedColumns: ["gateway_customer_id"];
          },
        ];
      };
      billing_prices: {
        Row: {
          active: boolean;
          amount: number;
          currency: string;
          free_trial_days: number | null;
          gateway_name: string;
          gateway_price_id: string;
          gateway_product_id: string;
          recurring_interval: string;
          recurring_interval_count: number;
          tier: string | null;
        };
        Insert: {
          active?: boolean;
          amount: number;
          currency: string;
          free_trial_days?: number | null;
          gateway_name: string;
          gateway_price_id?: string;
          gateway_product_id: string;
          recurring_interval: string;
          recurring_interval_count?: number;
          tier?: string | null;
        };
        Update: {
          active?: boolean;
          amount?: number;
          currency?: string;
          free_trial_days?: number | null;
          gateway_name?: string;
          gateway_price_id?: string;
          gateway_product_id?: string;
          recurring_interval?: string;
          recurring_interval_count?: number;
          tier?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "billing_prices_gateway_product_id_fkey";
            columns: ["gateway_product_id"];
            referencedRelation: "billing_products";
            referencedColumns: ["gateway_product_id"];
          },
        ];
      };
      billing_products: {
        Row: {
          active: boolean;
          description: string | null;
          features: Json | null;
          gateway_name: string;
          gateway_product_id: string;
          is_visible_in_ui: boolean;
          name: string;
        };
        Insert: {
          active?: boolean;
          description?: string | null;
          features?: Json | null;
          gateway_name: string;
          gateway_product_id: string;
          is_visible_in_ui?: boolean;
          name: string;
        };
        Update: {
          active?: boolean;
          description?: string | null;
          features?: Json | null;
          gateway_name?: string;
          gateway_product_id?: string;
          is_visible_in_ui?: boolean;
          name?: string;
        };
        Relationships: [];
      };
      billing_subscriptions: {
        Row: {
          cancel_at_period_end: boolean;
          currency: string;
          current_period_end: string;
          current_period_start: string;
          gateway_customer_id: string;
          gateway_name: string;
          gateway_price_id: string;
          gateway_product_id: string;
          gateway_subscription_id: string;
          id: string;
          is_trial: boolean;
          quantity: number | null;
          status: Database["public"]["Enums"]["subscription_status"];
          trial_ends_at: string | null;
        };
        Insert: {
          cancel_at_period_end: boolean;
          currency: string;
          current_period_end: string;
          current_period_start: string;
          gateway_customer_id: string;
          gateway_name: string;
          gateway_price_id: string;
          gateway_product_id: string;
          gateway_subscription_id: string;
          id?: string;
          is_trial: boolean;
          quantity?: number | null;
          status: Database["public"]["Enums"]["subscription_status"];
          trial_ends_at?: string | null;
        };
        Update: {
          cancel_at_period_end?: boolean;
          currency?: string;
          current_period_end?: string;
          current_period_start?: string;
          gateway_customer_id?: string;
          gateway_name?: string;
          gateway_price_id?: string;
          gateway_product_id?: string;
          gateway_subscription_id?: string;
          id?: string;
          is_trial?: boolean;
          quantity?: number | null;
          status?: Database["public"]["Enums"]["subscription_status"];
          trial_ends_at?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "billing_subscriptions_gateway_customer_id_fkey";
            columns: ["gateway_customer_id"];
            referencedRelation: "billing_customers";
            referencedColumns: ["gateway_customer_id"];
          },
          {
            foreignKeyName: "billing_subscriptions_gateway_price_id_fkey";
            columns: ["gateway_price_id"];
            referencedRelation: "billing_prices";
            referencedColumns: ["gateway_price_id"];
          },
          {
            foreignKeyName: "billing_subscriptions_gateway_product_id_fkey";
            columns: ["gateway_product_id"];
            referencedRelation: "billing_products";
            referencedColumns: ["gateway_product_id"];
          },
        ];
      };
      billing_usage_logs: {
        Row: {
          feature: string;
          gateway_customer_id: string;
          id: string;
          timestamp: string;
          usage_amount: number;
        };
        Insert: {
          feature: string;
          gateway_customer_id: string;
          id?: string;
          timestamp?: string;
          usage_amount: number;
        };
        Update: {
          feature?: string;
          gateway_customer_id?: string;
          id?: string;
          timestamp?: string;
          usage_amount?: number;
        };
        Relationships: [
          {
            foreignKeyName: "billing_usage_logs_gateway_customer_id_fkey";
            columns: ["gateway_customer_id"];
            referencedRelation: "billing_customers";
            referencedColumns: ["gateway_customer_id"];
          },
        ];
      };
      billing_volume_tiers: {
        Row: {
          gateway_price_id: string;
          id: string;
          max_quantity: number | null;
          min_quantity: number;
          unit_price: number;
        };
        Insert: {
          gateway_price_id: string;
          id?: string;
          max_quantity?: number | null;
          min_quantity: number;
          unit_price: number;
        };
        Update: {
          gateway_price_id?: string;
          id?: string;
          max_quantity?: number | null;
          min_quantity?: number;
          unit_price?: number;
        };
        Relationships: [
          {
            foreignKeyName: "billing_volume_tiers_gateway_price_id_fkey";
            columns: ["gateway_price_id"];
            referencedRelation: "billing_prices";
            referencedColumns: ["gateway_price_id"];
          },
        ];
      };
      chats: {
        Row: {
          created_at: string;
          id: string;
          payload: Json | null;
          project_id: string;
          user_id: string;
        };
        Insert: {
          created_at?: string;
          id: string;
          payload?: Json | null;
          project_id: string;
          user_id: string;
        };
        Update: {
          created_at?: string;
          id?: string;
          payload?: Json | null;
          project_id?: string;
          user_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "chats_project_id_fkey";
            columns: ["project_id"];
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "chats_user_id_fkey";
            columns: ["user_id"];
            referencedRelation: "user_profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      coding_sessions: {
        Row: {
          created_at: string;
          current_branch: string | null;
          device_id: string;
          id: string;
          last_heartbeat_at: string | null;
          repository_id: string;
          session_ended_at: string | null;
          session_pid: number | null;
          session_started_at: string;
          status: Database["public"]["Enums"]["coding_session_status"];
          updated_at: string;
          user_id: string;
          working_directory: string | null;
        };
        Insert: {
          created_at?: string;
          current_branch?: string | null;
          device_id: string;
          id?: string;
          last_heartbeat_at?: string | null;
          repository_id: string;
          session_ended_at?: string | null;
          session_pid?: number | null;
          session_started_at?: string;
          status?: Database["public"]["Enums"]["coding_session_status"];
          updated_at?: string;
          user_id: string;
          working_directory?: string | null;
        };
        Update: {
          created_at?: string;
          current_branch?: string | null;
          device_id?: string;
          id?: string;
          last_heartbeat_at?: string | null;
          repository_id?: string;
          session_ended_at?: string | null;
          session_pid?: number | null;
          session_started_at?: string;
          status?: Database["public"]["Enums"]["coding_session_status"];
          updated_at?: string;
          user_id?: string;
          working_directory?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "coding_sessions_device_id_fkey";
            columns: ["device_id"];
            referencedRelation: "devices";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "coding_sessions_repository_id_fkey";
            columns: ["repository_id"];
            referencedRelation: "repositories";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "coding_sessions_user_id_fkey";
            columns: ["user_id"];
            referencedRelation: "user_profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      devices: {
        Row: {
          created_at: string;
          device_type: Database["public"]["Enums"]["device_type"];
          fingerprint: string | null;
          hostname: string | null;
          id: string;
          is_active: boolean;
          last_seen_at: string | null;
          name: string;
          updated_at: string;
          user_id: string;
        };
        Insert: {
          created_at?: string;
          device_type: Database["public"]["Enums"]["device_type"];
          fingerprint?: string | null;
          hostname?: string | null;
          id?: string;
          is_active?: boolean;
          last_seen_at?: string | null;
          name: string;
          updated_at?: string;
          user_id: string;
        };
        Update: {
          created_at?: string;
          device_type?: Database["public"]["Enums"]["device_type"];
          fingerprint?: string | null;
          hostname?: string | null;
          id?: string;
          is_active?: boolean;
          last_seen_at?: string | null;
          name?: string;
          updated_at?: string;
          user_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "devices_user_id_fkey";
            columns: ["user_id"];
            referencedRelation: "user_profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      marketing_author_profiles: {
        Row: {
          avatar_url: string;
          bio: string;
          created_at: string;
          display_name: string;
          facebook_handle: string | null;
          id: string;
          instagram_handle: string | null;
          linkedin_handle: string | null;
          slug: string;
          twitter_handle: string | null;
          updated_at: string;
          website_url: string | null;
        };
        Insert: {
          avatar_url: string;
          bio: string;
          created_at?: string;
          display_name: string;
          facebook_handle?: string | null;
          id?: string;
          instagram_handle?: string | null;
          linkedin_handle?: string | null;
          slug: string;
          twitter_handle?: string | null;
          updated_at?: string;
          website_url?: string | null;
        };
        Update: {
          avatar_url?: string;
          bio?: string;
          created_at?: string;
          display_name?: string;
          facebook_handle?: string | null;
          id?: string;
          instagram_handle?: string | null;
          linkedin_handle?: string | null;
          slug?: string;
          twitter_handle?: string | null;
          updated_at?: string;
          website_url?: string | null;
        };
        Relationships: [];
      };
      marketing_blog_author_posts: {
        Row: {
          author_id: string;
          post_id: string;
        };
        Insert: {
          author_id: string;
          post_id: string;
        };
        Update: {
          author_id?: string;
          post_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "marketing_blog_author_posts_author_id_fkey";
            columns: ["author_id"];
            referencedRelation: "marketing_author_profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "marketing_blog_author_posts_post_id_fkey";
            columns: ["post_id"];
            referencedRelation: "marketing_blog_posts";
            referencedColumns: ["id"];
          },
        ];
      };
      marketing_blog_post_tags_relationship: {
        Row: {
          blog_post_id: string;
          tag_id: string;
        };
        Insert: {
          blog_post_id: string;
          tag_id: string;
        };
        Update: {
          blog_post_id?: string;
          tag_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "marketing_blog_post_tags_relationship_blog_post_id_fkey";
            columns: ["blog_post_id"];
            referencedRelation: "marketing_blog_posts";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "marketing_blog_post_tags_relationship_tag_id_fkey";
            columns: ["tag_id"];
            referencedRelation: "marketing_tags";
            referencedColumns: ["id"];
          },
        ];
      };
      marketing_blog_posts: {
        Row: {
          content: string;
          cover_image: string | null;
          created_at: string;
          id: string;
          is_featured: boolean;
          json_content: Json;
          media_poster: string | null;
          media_type: string | null;
          seo_data: Json | null;
          slug: string;
          status: Database["public"]["Enums"]["marketing_blog_post_status"];
          summary: string;
          title: string;
          updated_at: string;
        };
        Insert: {
          content: string;
          cover_image?: string | null;
          created_at?: string;
          id?: string;
          is_featured?: boolean;
          json_content?: Json;
          media_poster?: string | null;
          media_type?: string | null;
          seo_data?: Json | null;
          slug: string;
          status?: Database["public"]["Enums"]["marketing_blog_post_status"];
          summary: string;
          title: string;
          updated_at?: string;
        };
        Update: {
          content?: string;
          cover_image?: string | null;
          created_at?: string;
          id?: string;
          is_featured?: boolean;
          json_content?: Json;
          media_poster?: string | null;
          media_type?: string | null;
          seo_data?: Json | null;
          slug?: string;
          status?: Database["public"]["Enums"]["marketing_blog_post_status"];
          summary?: string;
          title?: string;
          updated_at?: string;
        };
        Relationships: [];
      };
      marketing_changelog: {
        Row: {
          cover_image: string | null;
          created_at: string | null;
          id: string;
          json_content: Json;
          media_alt: string | null;
          media_poster: string | null;
          media_type: string | null;
          media_url: string | null;
          status: Database["public"]["Enums"]["marketing_changelog_status"];
          tags: string[] | null;
          technical_details: string | null;
          title: string;
          updated_at: string | null;
          version: string | null;
        };
        Insert: {
          cover_image?: string | null;
          created_at?: string | null;
          id?: string;
          json_content?: Json;
          media_alt?: string | null;
          media_poster?: string | null;
          media_type?: string | null;
          media_url?: string | null;
          status?: Database["public"]["Enums"]["marketing_changelog_status"];
          tags?: string[] | null;
          technical_details?: string | null;
          title: string;
          updated_at?: string | null;
          version?: string | null;
        };
        Update: {
          cover_image?: string | null;
          created_at?: string | null;
          id?: string;
          json_content?: Json;
          media_alt?: string | null;
          media_poster?: string | null;
          media_type?: string | null;
          media_url?: string | null;
          status?: Database["public"]["Enums"]["marketing_changelog_status"];
          tags?: string[] | null;
          technical_details?: string | null;
          title?: string;
          updated_at?: string | null;
          version?: string | null;
        };
        Relationships: [];
      };
      marketing_changelog_author_relationship: {
        Row: {
          author_id: string;
          changelog_id: string;
        };
        Insert: {
          author_id: string;
          changelog_id: string;
        };
        Update: {
          author_id?: string;
          changelog_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "marketing_changelog_author_relationship_author_id_fkey";
            columns: ["author_id"];
            referencedRelation: "marketing_author_profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "marketing_changelog_author_relationship_changelog_id_fkey";
            columns: ["changelog_id"];
            referencedRelation: "marketing_changelog";
            referencedColumns: ["id"];
          },
        ];
      };
      marketing_feedback_board_subscriptions: {
        Row: {
          board_id: string;
          created_at: string;
          id: string;
          user_id: string;
        };
        Insert: {
          board_id: string;
          created_at?: string;
          id?: string;
          user_id: string;
        };
        Update: {
          board_id?: string;
          created_at?: string;
          id?: string;
          user_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "marketing_feedback_board_subscriptions_board_id_fkey";
            columns: ["board_id"];
            referencedRelation: "marketing_feedback_boards";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "marketing_feedback_board_subscriptions_user_id_fkey";
            columns: ["user_id"];
            referencedRelation: "user_profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      marketing_feedback_boards: {
        Row: {
          color: string | null;
          created_at: string;
          created_by: string;
          description: string | null;
          id: string;
          is_active: boolean;
          settings: Json;
          slug: string;
          title: string;
          updated_at: string;
        };
        Insert: {
          color?: string | null;
          created_at?: string;
          created_by: string;
          description?: string | null;
          id?: string;
          is_active?: boolean;
          settings?: Json;
          slug: string;
          title: string;
          updated_at?: string;
        };
        Update: {
          color?: string | null;
          created_at?: string;
          created_by?: string;
          description?: string | null;
          id?: string;
          is_active?: boolean;
          settings?: Json;
          slug?: string;
          title?: string;
          updated_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: "marketing_feedback_boards_created_by_fkey";
            columns: ["created_by"];
            referencedRelation: "user_profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      marketing_feedback_comment_reactions: {
        Row: {
          comment_id: string;
          created_at: string;
          id: string;
          reaction_type: Database["public"]["Enums"]["marketing_feedback_reaction_type"];
          user_id: string;
        };
        Insert: {
          comment_id: string;
          created_at?: string;
          id?: string;
          reaction_type: Database["public"]["Enums"]["marketing_feedback_reaction_type"];
          user_id: string;
        };
        Update: {
          comment_id?: string;
          created_at?: string;
          id?: string;
          reaction_type?: Database["public"]["Enums"]["marketing_feedback_reaction_type"];
          user_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "marketing_feedback_comment_reactions_comment_id_fkey";
            columns: ["comment_id"];
            referencedRelation: "marketing_feedback_comments";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "marketing_feedback_comment_reactions_user_id_fkey";
            columns: ["user_id"];
            referencedRelation: "user_profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      marketing_feedback_comments: {
        Row: {
          content: string;
          created_at: string;
          id: string;
          moderator_hold_category:
            | Database["public"]["Enums"]["marketing_feedback_moderator_hold_category"]
            | null;
          thread_id: string;
          updated_at: string;
          user_id: string;
        };
        Insert: {
          content: string;
          created_at?: string;
          id?: string;
          moderator_hold_category?:
            | Database["public"]["Enums"]["marketing_feedback_moderator_hold_category"]
            | null;
          thread_id: string;
          updated_at?: string;
          user_id: string;
        };
        Update: {
          content?: string;
          created_at?: string;
          id?: string;
          moderator_hold_category?:
            | Database["public"]["Enums"]["marketing_feedback_moderator_hold_category"]
            | null;
          thread_id?: string;
          updated_at?: string;
          user_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "marketing_feedback_comments_thread_id_fkey";
            columns: ["thread_id"];
            referencedRelation: "marketing_feedback_threads";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "marketing_feedback_comments_user_id_fkey";
            columns: ["user_id"];
            referencedRelation: "user_profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      marketing_feedback_thread_reactions: {
        Row: {
          created_at: string;
          id: string;
          reaction_type: Database["public"]["Enums"]["marketing_feedback_reaction_type"];
          thread_id: string;
          user_id: string;
        };
        Insert: {
          created_at?: string;
          id?: string;
          reaction_type: Database["public"]["Enums"]["marketing_feedback_reaction_type"];
          thread_id: string;
          user_id: string;
        };
        Update: {
          created_at?: string;
          id?: string;
          reaction_type?: Database["public"]["Enums"]["marketing_feedback_reaction_type"];
          thread_id?: string;
          user_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "marketing_feedback_thread_reactions_thread_id_fkey";
            columns: ["thread_id"];
            referencedRelation: "marketing_feedback_threads";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "marketing_feedback_thread_reactions_user_id_fkey";
            columns: ["user_id"];
            referencedRelation: "user_profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      marketing_feedback_thread_subscriptions: {
        Row: {
          created_at: string;
          id: string;
          thread_id: string;
          user_id: string;
        };
        Insert: {
          created_at?: string;
          id?: string;
          thread_id: string;
          user_id: string;
        };
        Update: {
          created_at?: string;
          id?: string;
          thread_id?: string;
          user_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "marketing_feedback_thread_subscriptions_thread_id_fkey";
            columns: ["thread_id"];
            referencedRelation: "marketing_feedback_threads";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "marketing_feedback_thread_subscriptions_user_id_fkey";
            columns: ["user_id"];
            referencedRelation: "user_profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      marketing_feedback_threads: {
        Row: {
          added_to_roadmap: boolean;
          board_id: string | null;
          content: string;
          created_at: string;
          id: string;
          is_publicly_visible: boolean;
          moderator_hold_category:
            | Database["public"]["Enums"]["marketing_feedback_moderator_hold_category"]
            | null;
          open_for_public_discussion: boolean;
          priority: Database["public"]["Enums"]["marketing_feedback_thread_priority"];
          status: Database["public"]["Enums"]["marketing_feedback_thread_status"];
          title: string;
          type: Database["public"]["Enums"]["marketing_feedback_thread_type"];
          updated_at: string;
          user_id: string;
        };
        Insert: {
          added_to_roadmap?: boolean;
          board_id?: string | null;
          content: string;
          created_at?: string;
          id?: string;
          is_publicly_visible?: boolean;
          moderator_hold_category?:
            | Database["public"]["Enums"]["marketing_feedback_moderator_hold_category"]
            | null;
          open_for_public_discussion?: boolean;
          priority?: Database["public"]["Enums"]["marketing_feedback_thread_priority"];
          status?: Database["public"]["Enums"]["marketing_feedback_thread_status"];
          title: string;
          type?: Database["public"]["Enums"]["marketing_feedback_thread_type"];
          updated_at?: string;
          user_id: string;
        };
        Update: {
          added_to_roadmap?: boolean;
          board_id?: string | null;
          content?: string;
          created_at?: string;
          id?: string;
          is_publicly_visible?: boolean;
          moderator_hold_category?:
            | Database["public"]["Enums"]["marketing_feedback_moderator_hold_category"]
            | null;
          open_for_public_discussion?: boolean;
          priority?: Database["public"]["Enums"]["marketing_feedback_thread_priority"];
          status?: Database["public"]["Enums"]["marketing_feedback_thread_status"];
          title?: string;
          type?: Database["public"]["Enums"]["marketing_feedback_thread_type"];
          updated_at?: string;
          user_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "marketing_feedback_threads_board_id_fkey";
            columns: ["board_id"];
            referencedRelation: "marketing_feedback_boards";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "marketing_feedback_threads_user_id_fkey";
            columns: ["user_id"];
            referencedRelation: "user_profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      marketing_tags: {
        Row: {
          description: string | null;
          id: string;
          name: string;
          slug: string;
        };
        Insert: {
          description?: string | null;
          id?: string;
          name: string;
          slug: string;
        };
        Update: {
          description?: string | null;
          id?: string;
          name?: string;
          slug?: string;
        };
        Relationships: [];
      };
      project_comments: {
        Row: {
          created_at: string | null;
          id: string;
          in_reply_to: string | null;
          project_id: string;
          text: string;
          user_id: string;
        };
        Insert: {
          created_at?: string | null;
          id?: string;
          in_reply_to?: string | null;
          project_id: string;
          text: string;
          user_id: string;
        };
        Update: {
          created_at?: string | null;
          id?: string;
          in_reply_to?: string | null;
          project_id?: string;
          text?: string;
          user_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "project_comments_in_reply_to_fkey";
            columns: ["in_reply_to"];
            referencedRelation: "project_comments";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "project_comments_project_id_fkey";
            columns: ["project_id"];
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "project_comments_user_id_fkey";
            columns: ["user_id"];
            referencedRelation: "user_profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      projects: {
        Row: {
          created_at: string;
          id: string;
          name: string;
          project_status: Database["public"]["Enums"]["project_status"];
          slug: string;
          updated_at: string;
          workspace_id: string;
        };
        Insert: {
          created_at?: string;
          id?: string;
          name: string;
          project_status?: Database["public"]["Enums"]["project_status"];
          slug?: string;
          updated_at?: string;
          workspace_id: string;
        };
        Update: {
          created_at?: string;
          id?: string;
          name?: string;
          project_status?: Database["public"]["Enums"]["project_status"];
          slug?: string;
          updated_at?: string;
          workspace_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "projects_workspace_id_fkey";
            columns: ["workspace_id"];
            referencedRelation: "workspaces";
            referencedColumns: ["id"];
          },
        ];
      };
      repositories: {
        Row: {
          created_at: string;
          default_branch: string | null;
          device_id: string;
          id: string;
          is_worktree: boolean;
          last_synced_at: string | null;
          local_path: string;
          name: string;
          parent_repository_id: string | null;
          remote_url: string | null;
          status: Database["public"]["Enums"]["repository_status"];
          updated_at: string;
          user_id: string;
          worktree_branch: string | null;
        };
        Insert: {
          created_at?: string;
          default_branch?: string | null;
          device_id: string;
          id?: string;
          is_worktree?: boolean;
          last_synced_at?: string | null;
          local_path: string;
          name: string;
          parent_repository_id?: string | null;
          remote_url?: string | null;
          status?: Database["public"]["Enums"]["repository_status"];
          updated_at?: string;
          user_id: string;
          worktree_branch?: string | null;
        };
        Update: {
          created_at?: string;
          default_branch?: string | null;
          device_id?: string;
          id?: string;
          is_worktree?: boolean;
          last_synced_at?: string | null;
          local_path?: string;
          name?: string;
          parent_repository_id?: string | null;
          remote_url?: string | null;
          status?: Database["public"]["Enums"]["repository_status"];
          updated_at?: string;
          user_id?: string;
          worktree_branch?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "repositories_device_id_fkey";
            columns: ["device_id"];
            referencedRelation: "devices";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "repositories_parent_repository_id_fkey";
            columns: ["parent_repository_id"];
            referencedRelation: "repositories";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "repositories_user_id_fkey";
            columns: ["user_id"];
            referencedRelation: "user_profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      user_api_keys: {
        Row: {
          created_at: string;
          expires_at: string | null;
          is_revoked: boolean;
          key_id: string;
          masked_key: string;
          user_id: string;
        };
        Insert: {
          created_at?: string;
          expires_at?: string | null;
          is_revoked?: boolean;
          key_id: string;
          masked_key: string;
          user_id: string;
        };
        Update: {
          created_at?: string;
          expires_at?: string | null;
          is_revoked?: boolean;
          key_id?: string;
          masked_key?: string;
          user_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "user_api_keys_user_id_fkey";
            columns: ["user_id"];
            referencedRelation: "user_profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      user_application_settings: {
        Row: {
          email_readonly: string;
          id: string;
        };
        Insert: {
          email_readonly: string;
          id: string;
        };
        Update: {
          email_readonly?: string;
          id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "user_application_settings_id_fkey";
            columns: ["id"];
            referencedRelation: "user_profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      user_notifications: {
        Row: {
          created_at: string;
          id: string;
          is_read: boolean;
          is_seen: boolean;
          payload: Json;
          updated_at: string;
          user_id: string;
        };
        Insert: {
          created_at?: string;
          id?: string;
          is_read?: boolean;
          is_seen?: boolean;
          payload?: Json;
          updated_at?: string;
          user_id: string;
        };
        Update: {
          created_at?: string;
          id?: string;
          is_read?: boolean;
          is_seen?: boolean;
          payload?: Json;
          updated_at?: string;
          user_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "user_notifications_user_id_fkey";
            columns: ["user_id"];
            referencedRelation: "user_profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      user_profiles: {
        Row: {
          avatar_url: string | null;
          created_at: string;
          full_name: string | null;
          id: string;
        };
        Insert: {
          avatar_url?: string | null;
          created_at?: string;
          full_name?: string | null;
          id: string;
        };
        Update: {
          avatar_url?: string | null;
          created_at?: string;
          full_name?: string | null;
          id?: string;
        };
        Relationships: [];
      };
      user_roles: {
        Row: {
          id: string;
          role: Database["public"]["Enums"]["app_role"];
          user_id: string;
        };
        Insert: {
          id?: string;
          role: Database["public"]["Enums"]["app_role"];
          user_id: string;
        };
        Update: {
          id?: string;
          role?: Database["public"]["Enums"]["app_role"];
          user_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "user_roles_user_id_fkey";
            columns: ["user_id"];
            referencedRelation: "user_profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      user_settings: {
        Row: {
          default_workspace: string | null;
          id: string;
        };
        Insert: {
          default_workspace?: string | null;
          id: string;
        };
        Update: {
          default_workspace?: string | null;
          id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "user_settings_default_workspace_fkey";
            columns: ["default_workspace"];
            referencedRelation: "workspaces";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "user_settings_id_fkey";
            columns: ["id"];
            referencedRelation: "user_profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      workspace_admin_settings: {
        Row: {
          workspace_id: string;
          workspace_settings: Json;
        };
        Insert: {
          workspace_id: string;
          workspace_settings?: Json;
        };
        Update: {
          workspace_id?: string;
          workspace_settings?: Json;
        };
        Relationships: [
          {
            foreignKeyName: "workspace_admin_settings_workspace_id_fkey";
            columns: ["workspace_id"];
            referencedRelation: "workspaces";
            referencedColumns: ["id"];
          },
        ];
      };
      workspace_application_settings: {
        Row: {
          membership_type: Database["public"]["Enums"]["workspace_membership_type"];
          workspace_id: string;
        };
        Insert: {
          membership_type?: Database["public"]["Enums"]["workspace_membership_type"];
          workspace_id: string;
        };
        Update: {
          membership_type?: Database["public"]["Enums"]["workspace_membership_type"];
          workspace_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "workspace_application_settings_workspace_id_fkey";
            columns: ["workspace_id"];
            referencedRelation: "workspaces";
            referencedColumns: ["id"];
          },
        ];
      };
      workspace_credits: {
        Row: {
          credits: number;
          id: string;
          last_reset_date: string | null;
          workspace_id: string;
        };
        Insert: {
          credits?: number;
          id?: string;
          last_reset_date?: string | null;
          workspace_id: string;
        };
        Update: {
          credits?: number;
          id?: string;
          last_reset_date?: string | null;
          workspace_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "workspace_credits_workspace_id_fkey";
            columns: ["workspace_id"];
            referencedRelation: "workspaces";
            referencedColumns: ["id"];
          },
        ];
      };
      workspace_credits_logs: {
        Row: {
          change_type: string;
          changed_at: string;
          id: string;
          new_credits: number | null;
          old_credits: number | null;
          workspace_credits_id: string;
          workspace_id: string;
        };
        Insert: {
          change_type: string;
          changed_at?: string;
          id?: string;
          new_credits?: number | null;
          old_credits?: number | null;
          workspace_credits_id: string;
          workspace_id: string;
        };
        Update: {
          change_type?: string;
          changed_at?: string;
          id?: string;
          new_credits?: number | null;
          old_credits?: number | null;
          workspace_credits_id?: string;
          workspace_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "workspace_credits_logs_workspace_credits_id_fkey";
            columns: ["workspace_credits_id"];
            referencedRelation: "workspace_credits";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "workspace_credits_logs_workspace_id_fkey";
            columns: ["workspace_id"];
            referencedRelation: "workspaces";
            referencedColumns: ["id"];
          },
        ];
      };
      workspace_invitations: {
        Row: {
          created_at: string;
          id: string;
          invitee_user_email: string;
          invitee_user_id: string | null;
          invitee_user_role: Database["public"]["Enums"]["workspace_member_role_type"];
          inviter_user_id: string;
          status: Database["public"]["Enums"]["workspace_invitation_link_status"];
          workspace_id: string;
        };
        Insert: {
          created_at?: string;
          id?: string;
          invitee_user_email: string;
          invitee_user_id?: string | null;
          invitee_user_role?: Database["public"]["Enums"]["workspace_member_role_type"];
          inviter_user_id: string;
          status?: Database["public"]["Enums"]["workspace_invitation_link_status"];
          workspace_id: string;
        };
        Update: {
          created_at?: string;
          id?: string;
          invitee_user_email?: string;
          invitee_user_id?: string | null;
          invitee_user_role?: Database["public"]["Enums"]["workspace_member_role_type"];
          inviter_user_id?: string;
          status?: Database["public"]["Enums"]["workspace_invitation_link_status"];
          workspace_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "workspace_invitations_invitee_user_id_fkey";
            columns: ["invitee_user_id"];
            referencedRelation: "user_profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "workspace_invitations_inviter_user_id_fkey";
            columns: ["inviter_user_id"];
            referencedRelation: "user_profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "workspace_invitations_workspace_id_fkey";
            columns: ["workspace_id"];
            referencedRelation: "workspaces";
            referencedColumns: ["id"];
          },
        ];
      };
      workspace_members: {
        Row: {
          added_at: string;
          id: string;
          permissions: Json;
          workspace_id: string;
          workspace_member_id: string;
          workspace_member_role: Database["public"]["Enums"]["workspace_member_role_type"];
        };
        Insert: {
          added_at?: string;
          id?: string;
          permissions?: Json;
          workspace_id: string;
          workspace_member_id: string;
          workspace_member_role: Database["public"]["Enums"]["workspace_member_role_type"];
        };
        Update: {
          added_at?: string;
          id?: string;
          permissions?: Json;
          workspace_id?: string;
          workspace_member_id?: string;
          workspace_member_role?: Database["public"]["Enums"]["workspace_member_role_type"];
        };
        Relationships: [
          {
            foreignKeyName: "workspace_members_workspace_id_fkey";
            columns: ["workspace_id"];
            referencedRelation: "workspaces";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "workspace_members_workspace_member_id_fkey";
            columns: ["workspace_member_id"];
            referencedRelation: "user_profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      workspace_settings: {
        Row: {
          workspace_id: string;
          workspace_settings: Json;
        };
        Insert: {
          workspace_id: string;
          workspace_settings?: Json;
        };
        Update: {
          workspace_id?: string;
          workspace_settings?: Json;
        };
        Relationships: [
          {
            foreignKeyName: "workspace_settings_workspace_id_fkey";
            columns: ["workspace_id"];
            referencedRelation: "workspaces";
            referencedColumns: ["id"];
          },
        ];
      };
      workspaces: {
        Row: {
          created_at: string;
          id: string;
          name: string;
          slug: string;
        };
        Insert: {
          created_at?: string;
          id?: string;
          name: string;
          slug?: string;
        };
        Update: {
          created_at?: string;
          id?: string;
          name?: string;
          slug?: string;
        };
        Relationships: [];
      };
    };
    Views: {
      [_ in never]: never;
    };
    Functions: {
      app_admin_get_projects_created_per_month: {
        Args: Record<PropertyKey, never>;
        Returns: {
          month: string;
          number_of_projects: number;
        }[];
      };
      app_admin_get_recent_30_day_signin_count: {
        Args: Record<PropertyKey, never>;
        Returns: number;
      };
      app_admin_get_total_organization_count: {
        Args: Record<PropertyKey, never>;
        Returns: number;
      };
      app_admin_get_total_project_count: {
        Args: Record<PropertyKey, never>;
        Returns: number;
      };
      app_admin_get_total_user_count: {
        Args: Record<PropertyKey, never>;
        Returns: number;
      };
      app_admin_get_user_id_by_email: {
        Args: { emailarg: string };
        Returns: string;
      };
      app_admin_get_users_created_per_month: {
        Args: Record<PropertyKey, never>;
        Returns: {
          month: string;
          number_of_users: number;
        }[];
      };
      app_admin_get_workspaces_created_per_month: {
        Args: Record<PropertyKey, never>;
        Returns: {
          month: string;
          number_of_workspaces: number;
        }[];
      };
      check_if_authenticated_user_owns_email: {
        Args: { email: string };
        Returns: boolean;
      };
      custom_access_token_hook: { Args: { event: Json }; Returns: Json };
      decrement_credits: {
        Args: { amount: number; org_id: string };
        Returns: undefined;
      };
      get_customer_workspace_id: {
        Args: { customer_id_arg: string };
        Returns: string;
      };
      get_project_workspace_uuid: {
        Args: { project_id: string };
        Returns: string;
      };
      get_workspace_team_member_admins: {
        Args: { workspace_id: string };
        Returns: {
          member_id: string;
        }[];
      };
      get_workspace_team_member_ids: {
        Args: { workspace_id: string };
        Returns: {
          member_id: string;
        }[];
      };
      has_workspace_permission: {
        Args: { permission: string; user_id: string; workspace_id: string };
        Returns: boolean;
      };
      is_application_admin: { Args: { user_id?: string }; Returns: boolean };
      is_workspace_admin: {
        Args: { user_id: string; workspace_id: string };
        Returns: boolean;
      };
      is_workspace_member: {
        Args: { user_id: string; workspace_id: string };
        Returns: boolean;
      };
      make_user_app_admin: {
        Args: { user_id_arg: string };
        Returns: undefined;
      };
      remove_app_admin_privilege_for_user: {
        Args: { user_id_arg: string };
        Returns: undefined;
      };
      update_workspace_member_permissions: {
        Args: {
          member_id: string;
          new_permissions: Json;
          workspace_id: string;
        };
        Returns: undefined;
      };
    };
    Enums: {
      app_role: "admin";
      coding_session_status: "active" | "paused" | "ended";
      device_type: "mac" | "linux" | "windows" | "cli";
      marketing_blog_post_status: "draft" | "published";
      marketing_changelog_status: "draft" | "published";
      marketing_feedback_moderator_hold_category:
        | "spam"
        | "off_topic"
        | "inappropriate"
        | "other";
      marketing_feedback_reaction_type:
        | "like"
        | "heart"
        | "celebrate"
        | "upvote";
      marketing_feedback_thread_priority: "low" | "medium" | "high";
      marketing_feedback_thread_status:
        | "open"
        | "under_review"
        | "planned"
        | "closed"
        | "in_progress"
        | "completed"
        | "moderator_hold";
      marketing_feedback_thread_type: "bug" | "feature_request" | "general";
      organization_joining_status:
        | "invited"
        | "joinied"
        | "declined_invitation"
        | "joined";
      organization_member_role: "owner" | "admin" | "member" | "readonly";
      pricing_plan_interval: "day" | "week" | "month" | "year";
      pricing_type: "one_time" | "recurring";
      project_status: "draft" | "pending_approval" | "approved" | "completed";
      project_team_member_role: "admin" | "member" | "readonly";
      repository_status: "active" | "archived";
      subscription_status:
        | "trialing"
        | "active"
        | "canceled"
        | "incomplete"
        | "incomplete_expired"
        | "past_due"
        | "unpaid"
        | "paused";
      workspace_invitation_link_status:
        | "active"
        | "finished_accepted"
        | "finished_declined"
        | "inactive";
      workspace_member_role_type: "owner" | "admin" | "member" | "readonly";
      workspace_membership_type: "solo" | "team";
    };
    CompositeTypes: {
      [_ in never]: never;
    };
  };
};

type DefaultSchema = Database[Extract<keyof Database, "public">];

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof Database },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof Database;
  }
    ? keyof (Database[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        Database[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends { schema: keyof Database }
  ? (Database[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      Database[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R;
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R;
      }
      ? R
      : never
    : never;

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof Database },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof Database;
  }
    ? keyof Database[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends { schema: keyof Database }
  ? Database[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I;
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I;
      }
      ? I
      : never
    : never;

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof Database },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof Database;
  }
    ? keyof Database[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends { schema: keyof Database }
  ? Database[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U;
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U;
      }
      ? U
      : never
    : never;

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof Database },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof Database;
  }
    ? keyof Database[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends { schema: keyof Database }
  ? Database[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never;

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof Database },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof Database;
  }
    ? keyof Database[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends { schema: keyof Database }
  ? Database[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never;
