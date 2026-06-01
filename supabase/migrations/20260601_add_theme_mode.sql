-- Migration: Add theme_mode column to teachers table
-- Run this in the Supabase SQL Editor via Dashboard > SQL Editor

ALTER TABLE public.teachers ADD COLUMN IF NOT EXISTS theme_mode TEXT DEFAULT 'system';
