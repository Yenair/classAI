/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

import React, { useState } from 'react';
import { 
  Home, 
  BookOpen, 
  ShieldCheck, 
  Archive, 
  Settings, 
  User, 
  Upload, 
  Image as ImageIcon, 
  Eye, 
  Send,
  History,
  CheckCircle2,
  Clock,
  AlertCircle,
  Menu,
  ChevronDown,
  RefreshCw
} from 'lucide-react';
import { motion, AnimatePresence } from 'motion/react';

const SidebarItem = ({ icon: Icon, label, active = false }: { icon: any, label: string, active?: boolean }) => (
  <div className={`flex items-center gap-4 px-4 py-3 mx-3 rounded-full cursor-pointer transition-all ${
    active 
      ? 'bg-secondary-fixed text-on-secondary-fixed font-bold' 
      : 'text-on-surface-variant hover:bg-surface-variant'
  }`}>
    <Icon size={24} strokeWidth={active ? 2.5 : 2} />
    <span className="text-label-lg font-medium">{label}</span>
  </div>
);

const NavItemMobile = ({ icon: Icon, label, active = false }: { icon: any, label: string, active?: boolean }) => (
  <div className={`flex flex-col items-center justify-center py-2 w-16 transition-all ${
    active 
      ? 'bg-secondary-container text-on-secondary-container rounded-2xl scale-95 shadow-sm px-4' 
      : 'text-on-surface-variant'
  }`}>
    <Icon size={24} />
    <span className="text-[10px] mt-1 font-medium">{label}</span>
  </div>
);

const SubmissionCard = ({ title, status, date, error }: { title: string, status: 'Pending' | 'Approved' | 'Rejected', date: string, error?: string }) => {
  const statusConfig = {
    Pending: { color: 'bg-surface-variant text-on-surface-variant', dot: 'bg-gray-400' },
    Approved: { color: 'bg-secondary-container text-on-secondary-container', dot: 'bg-green-600' },
    Rejected: { color: 'bg-error-container text-on-error-container', dot: 'bg-error', errorBorder: 'border-error/20' }
  };

  const config = statusConfig[status];

  return (
    <div className={`p-4 rounded-xl bg-surface-container-lowest border border-outline-variant/30 hover:shadow-md transition-all ${status === 'Rejected' ? 'border-error/20' : ''}`}>
      <div className="flex justify-between items-start mb-2 gap-2">
        <h4 className="text-label-lg text-on-surface font-bold truncate flex-1">{title}</h4>
        <span className={`shrink-0 px-2 py-0.5 rounded text-[10px] font-bold uppercase tracking-wider flex items-center gap-1.5 ${config.color}`}>
          <div className={`w-1.5 h-1.5 rounded-full ${config.dot}`} />
          {status}
        </span>
      </div>
      <p className="text-label-md text-outline">{date}</p>
      {error && (
        <p className="text-label-md text-error bg-error-container/20 p-2 rounded mt-2 font-medium">
          {error}
        </p>
      )}
    </div>
  );
};

export default function App() {
  const [isMobileMenuOpen, setIsMobileMenuOpen] = useState(false);

  return (
    <div className="bg-background text-on-background min-h-screen flex flex-col md:flex-row font-body selection:bg-primary/20">
      {/* Navigation Drawer (Tablet/Desktop) */}
      <nav className="hidden md:flex flex-col h-screen border-r border-outline-variant/30 py-8 bg-surface-container-low w-72 shrink-0 sticky top-0">
        <div className="px-6 mb-10">
          <h1 className="text-headline font-black text-primary text-3xl tracking-tight">ClassAI</h1>
          <p className="text-label-md text-on-surface-variant opacity-70">Nigerian Academic Partner</p>
        </div>
        
        <div className="flex-1 flex flex-col gap-1 overflow-y-auto">
          <SidebarItem icon={Home} label="Home" />
          <SidebarItem icon={BookOpen} label="Lessons" />
          <SidebarItem icon={ShieldCheck} label="Exams" />
          <SidebarItem icon={Archive} label="Vault" active />
          <SidebarItem icon={Settings} label="Admin" />
        </div>

        <div className="px-6 mt-auto">
          <div className="flex items-center gap-3 p-3 rounded-2xl bg-surface-container-high border border-outline-variant/30">
            <div className="w-10 h-10 rounded-full bg-primary flex items-center justify-center text-white font-black">E</div>
            <div className="flex-1 min-w-0">
              <p className="text-label-lg font-bold truncate">Educator</p>
              <p className="text-[10px] text-on-surface-variant">Active Session</p>
            </div>
          </div>
        </div>
      </nav>

      {/* TopAppBar (Mobile) */}
      <header className="md:hidden flex justify-between items-center w-full px-4 h-16 bg-surface-container sticky top-0 z-50 border-b border-outline-variant/20">
        <div className="flex items-center gap-3">
          <div className="w-8 h-8 rounded-full bg-surface-variant flex items-center justify-center">
            <User size={18} className="text-on-surface-variant" />
          </div>
          <h1 className="text-title-lg font-bold text-primary">ClassAI</h1>
        </div>
        <div className="flex items-center gap-4">
          <div className="text-label-lg font-bold text-primary bg-primary/5 px-3 py-1 rounded-full">₦520</div>
          <button onClick={() => setIsMobileMenuOpen(!isMobileMenuOpen)}>
            <Menu size={24} className="text-on-surface-variant" />
          </button>
        </div>
      </header>

      {/* Main Content */}
      <main className="flex-1 w-full max-w-6xl mx-auto p-4 md:p-10 pb-24 md:pb-10 overflow-y-auto">
        <motion.header 
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          className="mb-10 max-w-2xl"
        >
          <h2 className="text-3xl md:text-4xl font-headline font-bold text-on-surface mb-3 tracking-tight">Vault Publisher</h2>
          <p className="text-body-lg text-on-surface-variant leading-relaxed">
            Publish academic resources to the national curriculum repository. 
            Ensuring every school has access to quality content.
          </p>
        </motion.header>

        <div className="grid grid-cols-1 lg:grid-cols-12 gap-8">
          {/* Main Form Area */}
          <div className="lg:col-span-8 space-y-6">
            <motion.div 
              initial={{ opacity: 0, scale: 0.98 }}
              animate={{ opacity: 1, scale: 1 }}
              transition={{ delay: 0.1 }}
              className="bg-surface-container-low/50 backdrop-blur-sm rounded-3xl p-6 md:p-8 border border-outline-variant/20"
            >
              <form className="space-y-6" onSubmit={(e) => e.preventDefault()}>
                {/* Title */}
                <div className="space-y-2">
                  <label className="block text-label-lg font-bold text-on-surface/80 px-1" htmlFor="title">Resource Title</label>
                  <input 
                    className="w-full h-14 rounded-2xl border-outline-variant bg-surface-container-lowest px-4 text-body-md focus:border-primary focus:ring-4 focus:ring-primary/10 transition-all outline-none"
                    id="title" 
                    placeholder="e.g., SS2 Biology Term 1 Notes" 
                    type="text"
                  />
                </div>

                {/* Subject & Class Level */}
                <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                  <div className="space-y-2">
                    <label className="block text-label-lg font-bold text-on-surface/80 px-1" htmlFor="subject">Subject</label>
                    <div className="relative">
                      <select 
                        className="w-full h-14 appearance-none rounded-2xl border-outline-variant bg-surface-container-lowest px-4 text-body-md focus:border-primary focus:ring-4 focus:ring-primary/10 transition-all outline-none"
                        id="subject"
                      >
                        <option disabled selected value="">Select subject...</option>
                        <option value="math">Mathematics</option>
                        <option value="english">English Language</option>
                        <option value="biology">Biology</option>
                        <option value="physics">Physics</option>
                        <option value="chemistry">Chemistry</option>
                      </select>
                      <ChevronDown size={20} className="absolute right-4 top-1/2 -translate-y-1/2 text-outline pointer-events-none" />
                    </div>
                  </div>
                  <div className="space-y-2">
                    <label className="block text-label-lg font-bold text-on-surface/80 px-1" htmlFor="class_level">Class Level</label>
                    <div className="relative">
                      <select 
                        className="w-full h-14 appearance-none rounded-2xl border-outline-variant bg-surface-container-lowest px-4 text-body-md focus:border-primary focus:ring-4 focus:ring-primary/10 transition-all outline-none"
                        id="class_level"
                      >
                        <option disabled selected value="">Select class...</option>
                        <option value="jss1">JSS 1</option>
                        <option value="jss2">JSS 2</option>
                        <option value="ss1">SS 1</option>
                        <option value="ss2">SS 2</option>
                      </select>
                      <ChevronDown size={20} className="absolute right-4 top-1/2 -translate-y-1/2 text-outline pointer-events-none" />
                    </div>
                  </div>
                </div>

                {/* Description */}
                <div className="space-y-2">
                  <label className="block text-label-lg font-bold text-on-surface/80 px-1" htmlFor="description">Description</label>
                  <textarea 
                    className="w-full rounded-2xl border-outline-variant bg-surface-container-lowest px-4 py-4 text-body-md focus:border-primary focus:ring-4 focus:ring-primary/10 transition-all outline-none min-h-[140px]"
                    id="description" 
                    placeholder="Provide a brief overview of the resource content..."
                  ></textarea>
                </div>

                {/* Content Upload Area */}
                <div className="space-y-2">
                  <label className="block text-label-lg font-bold text-on-surface/80 px-1">Resource Content</label>
                  <div className="border-2 border-dashed border-outline-variant rounded-3xl bg-surface-container-lowest p-10 text-center hover:bg-primary/5 hover:border-primary/50 transition-all cursor-pointer group flex flex-col items-center justify-center min-h-[180px]">
                    <div className="w-14 h-14 rounded-2xl bg-surface-container flex items-center justify-center mb-4 group-hover:scale-110 transition-transform shadow-sm">
                      <Upload size={28} className="text-on-surface-variant group-hover:text-primary transition-colors" />
                    </div>
                    <p className="text-body-md font-bold text-on-surface">Tap to upload PDF or Document</p>
                    <p className="text-label-md text-on-surface-variant mt-1.5 opacity-60">Supports .pdf, .docx, .ppt (Max 10MB)</p>
                  </div>
                </div>

                {/* Image Picker */}
                <div className="space-y-2">
                  <label className="block text-label-lg font-bold text-on-surface/80 px-1">Cover Image (Optional)</label>
                  <div className="flex items-center gap-6 p-4 rounded-2xl bg-surface-container-lowest border border-outline-variant/30">
                    <div className="w-20 h-20 rounded-xl bg-surface-container flex items-center justify-center overflow-hidden shrink-0 shadow-inner">
                      <ImageIcon size={32} className="text-outline opacity-40" />
                    </div>
                    <div className="flex-1">
                      <button className="h-11 px-6 rounded-xl border-2 border-primary text-label-lg font-bold text-primary hover:bg-primary hover:text-white transition-all active:scale-95" type="button">
                        Choose Image
                      </button>
                      <p className="text-label-md text-error mt-2 flex items-center gap-1.5 font-medium">
                        <AlertCircle size={14} />
                        Strict limit: 50KB for remote school access.
                      </p>
                    </div>
                  </div>
                </div>

                {/* Actions */}
                <div className="pt-8 flex flex-col sm:flex-row items-center justify-end gap-3 border-t border-outline-variant/30">
                  <button className="w-full sm:w-auto h-14 px-8 rounded-full border-2 border-outline-variant text-label-lg font-bold text-on-surface-variant hover:bg-surface-variant/50 transition-all flex items-center justify-center gap-2" type="button">
                    <Eye size={20} />
                    Preview
                  </button>
                  <button className="w-full sm:w-auto h-14 px-10 rounded-full bg-primary text-on-primary text-label-lg font-bold hover:bg-primary-container transition-all shadow-lg shadow-primary/20 flex items-center justify-center gap-2 active:scale-95" type="submit">
                    <Send size={20} />
                    Publish to Vault
                  </button>
                </div>
              </form>
            </motion.div>
          </div>

          {/* Side Panel: Tracker */}
          <div className="lg:col-span-4 space-y-6">
            <motion.div 
               initial={{ opacity: 0, x: 20 }}
               animate={{ opacity: 1, x: 0 }}
               transition={{ delay: 0.2 }}
               className="bg-surface-container rounded-3xl p-6 border border-outline-variant/20 sticky top-10"
            >
              <h3 className="text-title-lg font-headline font-bold text-on-background mb-6 flex items-center gap-3">
                <History size={24} className="text-primary" />
                Recent Submissions
              </h3>
              
              <div className="space-y-4">
                <SubmissionCard 
                  title="SS1 Chemistry Practicals" 
                  status="Pending" 
                  date="Submitted: Today, 09:45 AM" 
                />
                <SubmissionCard 
                  title="JSS3 Math Revision Guide" 
                  status="Approved" 
                  date="Submitted: Yesterday" 
                />
                <SubmissionCard 
                  title="English Essay Topics" 
                  status="Rejected" 
                  date="Submitted: Oct 12" 
                  error="Image size exceeds 50KB limit."
                />
              </div>

              <div className="mt-10 pt-6 border-t border-outline-variant/30">
                <div className="flex items-center gap-3 text-label-md text-outline font-medium">
                  <div className="relative">
                    <RefreshCw size={14} className="text-primary animate-spin" />
                  </div>
                  EmergencyFlushService Active
                </div>
                <p className="text-[10px] text-outline mt-2 leading-relaxed italic">
                  Background Sync is maintaining your local curriculum queue.
                </p>
              </div>
            </motion.div>
          </div>
        </div>
      </main>

      {/* BottomNavBar (Mobile) */}
      <nav className="fixed bottom-0 left-0 w-full z-50 flex justify-around items-center h-[80px] px-2 pb-2 md:hidden bg-surface-container-low border-t border-outline-variant/20 rounded-t-[32px] shadow-[0_-8px_32px_rgba(0,0,0,0.1)]">
        <NavItemMobile icon={Home} label="Home" />
        <NavItemMobile icon={BookOpen} label="Lessons" />
        <NavItemMobile icon={ShieldCheck} label="Exams" />
        <NavItemMobile icon={Archive} label="Vault" active />
        <NavItemMobile icon={ChevronDown} label="More" />
      </nav>
    </div>
  );
}
