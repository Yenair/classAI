-- Migration: add temp_password column to teachers table
-- Run this in the Supabase SQL Editor or via supabase db push

ALTER TABLE public.teachers
  ADD COLUMN IF NOT EXISTS temp_password TEXT;
