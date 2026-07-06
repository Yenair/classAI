#!/usr/bin/env python3
"""
Generate Master's Thesis DOCX for:
CLASSAI: AI CURRICULUM-AWARE LESSON NOTES GENERATOR FOR NIGERIAN SECONDARY SCHOOLS
"""

from docx import Document
from docx.shared import Inches, Pt, Cm, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.enum.section import WD_ORIENT
from docx.oxml.ns import qn, nsdecls
from docx.oxml import parse_xml
import datetime

doc = Document()

# ───────────────────────────────────────────────────────────────
# STYLES SETUP
# ───────────────────────────────────────────────────────────────
style = doc.styles['Normal']
font = style.font
font.name = 'Times New Roman'
font.size = Pt(12)
style.paragraph_format.line_spacing = 1.5
style.paragraph_format.space_after = Pt(0)
style.paragraph_format.space_before = Pt(0)

for level in range(1, 4):
    h = doc.styles[f'Heading {level}']
    h.font.name = 'Times New Roman'
    h.font.color.rgb = RGBColor(0, 0, 0)
    h.font.bold = True
    h.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.CENTER if level == 1 else WD_ALIGN_PARAGRAPH.LEFT
    h.paragraph_format.line_spacing = 1.5
    if level == 1:
        h.font.size = Pt(14)
    elif level == 2:
        h.font.size = Pt(13)
    else:
        h.font.size = Pt(12)


def add_centered_text(text, size=12, bold=False, space_after=6):
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.space_after = Pt(space_after)
    p.paragraph_format.line_spacing = 1.5
    run = p.add_run(text)
    run.font.name = 'Times New Roman'
    run.font.size = Pt(size)
    run.bold = bold
    return p


def add_justified_text(text, size=12, bold=False, indent_first=True):
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
    p.paragraph_format.line_spacing = 1.5
    p.paragraph_format.space_after = Pt(6)
    if indent_first:
        p.paragraph_format.first_line_indent = Cm(1.27)
    run = p.add_run(text)
    run.font.name = 'Times New Roman'
    run.font.size = Pt(size)
    run.bold = bold
    return p


def add_bullet(text, level=0):
    p = doc.add_paragraph(text, style='List Bullet')
    p.paragraph_format.line_spacing = 1.5
    p.paragraph_format.left_indent = Cm(1.27 + level * 1.27)
    for run in p.runs:
        run.font.name = 'Times New Roman'
        run.font.size = Pt(12)
    return p


def add_table_row(table, cells_text, bold=False):
    row = table.add_row()
    for i, text in enumerate(cells_text):
        cell = row.cells[i]
        cell.text = ''
        p = cell.paragraphs[0]
        run = p.add_run(text)
        run.font.name = 'Times New Roman'
        run.font.size = Pt(11)
        run.bold = bold
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    return row


# ───────────────────────────────────────────────────────────────
# TITLE PAGE
# ───────────────────────────────────────────────────────────────
for _ in range(4):
    doc.add_paragraph()

add_centered_text('CLASSAI: AI CURRICULUM-AWARE LESSON NOTES', size=16, bold=True, space_after=2)
add_centered_text('GENERATOR FOR NIGERIAN SECONDARY SCHOOLS', size=16, bold=True, space_after=12)

add_centered_text('BY', size=14, bold=False, space_after=6)
add_centered_text('Umoh, Yeneabasi Alex', size=14, bold=False, space_after=6)
add_centered_text('20/EG/CO/1359', size=13, bold=False, space_after=12)

add_centered_text('A PROJECT REPORT', size=13, bold=False, space_after=6)
add_centered_text('PRESENTED TO THE DEPARTMENT OF COMPUTER ENGINEERING', size=12, bold=False, space_after=6)
add_centered_text('FACULTY OF ENGINEERING', size=12, bold=False, space_after=6)
add_centered_text('[PLACEHOLDER: University Name]', size=12, bold=False, space_after=6)
add_centered_text('Uyo, Akwa Ibom State, Nigeria', size=12, bold=False, space_after=12)

add_centered_text('IN PARTIAL FULFILMENT OF THE REQUIREMENTS', size=12, bold=False, space_after=4)
add_centered_text('FOR THE AWARD OF THE DEGREE OF', size=12, bold=False, space_after=4)
add_centered_text('BACHELOR OF ENGINEERING (B.ENG) IN COMPUTER ENGINEERING', size=12, bold=False, space_after=12)

add_centered_text('July, 2026', size=12, bold=False, space_after=6)

doc.add_page_break()

# ───────────────────────────────────────────────────────────────
# TABLE OF CONTENTS
# ───────────────────────────────────────────────────────────────
doc.add_heading('TABLE OF CONTENTS', level=1)
toc_items = [
    ('Title Page', 'i'),
    ('Table of Contents', 'ii'),
    ('Abstract', 'iii'),
    ('CHAPTER 1: INTRODUCTION', '1'),
    ('    1.1 Background to the Study', '1'),
    ('    1.2 Statement of the Problem', '3'),
    ('    1.3 Aim and Objectives of the Study', '4'),
    ('    1.4 Research Questions', '5'),
    ('    1.5 Significance of the Study', '5'),
    ('    1.6 Scope and Delimitation', '6'),
    ('    1.7 Organisation of the Report', '6'),
    ('CHAPTER 2: LITERATURE REVIEW', '7'),
    ('    2.1 Review of Related Literature', '7'),
    ('    2.2 Theoretical Framework', '17'),
    ('    2.3 Summary of Literature Review', '19'),
    ('CHAPTER 3: METHODOLOGY', '20'),
    ('    3.1 Research Design', '20'),
    ('    3.2 System Architecture and Design', '20'),
    ('    3.3 Implementation Details', '24'),
    ('    3.4 Technology Stack', '26'),
    ('CHAPTER 4: SYSTEM DEVELOPMENT AND RESULTS', '27'),
    ('    4.1 System Implementation Results', '27'),
    ('    4.2 Feature Mapping to Research Literature', '30'),
    ('    4.3 Discussion of Findings', '32'),
    ('CHAPTER 5: SUMMARY, RECOMMENDATION AND CONCLUSION', '34'),
    ('    5.1 Summary of the Study', '34'),
    ('    5.2 Conclusion', '35'),
    ('    5.3 Contributions to Knowledge', '35'),
    ('    5.4 Recommendations', '36'),
    ('    5.5 Limitations of the Study', '37'),
    ('    5.6 Suggestions for Future Research', '37'),
    ('References', '38'),
    ('Appendices', '42'),
]
for item, page in toc_items:
    p = doc.add_paragraph()
    p.paragraph_format.line_spacing = 1.5
    p.paragraph_format.tab_stops.add_tab_stop(Cm(15), alignment=WD_ALIGN_PARAGRAPH.RIGHT, leader=1)
    run = p.add_run(f'{item}\t{page}')
    run.font.name = 'Times New Roman'
    run.font.size = Pt(12)

doc.add_page_break()

# ───────────────────────────────────────────────────────────────
# ABSTRACT
# ───────────────────────────────────────────────────────────────
doc.add_heading('ABSTRACT', level=1)
add_justified_text(
    'The integration of Artificial Intelligence (AI) in educational content generation presents '
    'a transformative opportunity for improving teaching quality in secondary schools. This project '
    'focuses on the design and development of ClassAI, an AI-powered, curriculum-aware lesson notes '
    'generator specifically tailored for Nigerian secondary schools operating under the Nigerian '
    'Educational Research and Development Council (NERDC) curriculum framework. The system addresses '
    'the critical challenge of standardised, high-quality lesson note preparation that many Nigerian '
    'teachers face due to large class sizes, limited resources, and insufficient planning time.'
)
add_justified_text(
    'ClassAI was developed as a cross-platform mobile application using Flutter and Dart, employing a '
    'three-tier architecture comprising a local SQLite database (via Drift ORM), a Supabase cloud '
    'backend, and an AI generation engine that supports both DeepSeek and Gemini large language models '
    'with automatic failover. The system incorporates offline-first capabilities, secure end-to-end '
    'encryption using AES-256-GCM, Argon2id key derivation, and a conflict-free replicated data '
    'synchronisation mechanism designed for intermittent internet connectivity typical in Nigerian '
    'educational settings. The application supports multi-curriculum generation including NERDC '
    '(Nigeria), Cambridge International, and Common Core State Standards (CCSS), with Bloom\'s '
    'Taxonomy-aligned cognitive level targeting.'
)
add_justified_text(
    'The research methodology employed a design science research approach, combining iterative system '
    'development with a comprehensive review of ten recent research papers on AI in education. The '
    'system architecture and features were designed based on insights from these studies, covering '
    'curriculum-informed AI, generative AI-powered educational alignment, AI in curriculum development, '
    'AI-assisted lesson generation, human-AI collaboration in education, and personalised learning. '
    'The project demonstrates how findings from contemporary AI education research can be synthesised '
    'and implemented in a practical, offline-first application tailored to the Nigerian educational context.'
)
add_justified_text(
    'Keywords: Artificial Intelligence, Lesson Notes Generation, NERDC Curriculum, Nigerian Secondary '
    'Education, Offline-First Architecture, Large Language Models, Educational Technology, '
    'Curriculum-Aware AI'
)

doc.add_page_break()

# ═══════════════════════════════════════════════════════════════
# CHAPTER 1: INTRODUCTION
# ═══════════════════════════════════════════════════════════════
doc.add_heading('CHAPTER 1', level=1)
doc.add_heading('INTRODUCTION', level=1)

doc.add_heading('1.1 Background to the Study', level=2)
add_justified_text(
    'Education remains the bedrock of national development, and the quality of instruction delivered '
    'in secondary schools directly impacts the human capital development of any nation. In Nigeria, '
    'the secondary education system is governed by the National Policy on Education (NPE), which '
    'stipulates a standardised curriculum developed and maintained by the Nigerian Educational Research '
    'and Development Council (NERDC). This curriculum defines the learning objectives, content, and '
    'assessment standards for all subjects taught across Junior Secondary School (JSS) and Senior '
    'Secondary School (SSS) levels.'
)
add_justified_text(
    'A critical component of effective teaching is the preparation of comprehensive lesson notes — '
    'structured documents that outline learning objectives, instructional materials, presentation '
    'procedures, assessment methods, and homework assignments for each lesson. According to the '
    'Teachers Registration Council of Nigeria (TRCN), proper lesson note preparation is a mandatory '
    'professional requirement for all practicing teachers. However, many Nigerian teachers struggle '
    'with this task due to several compounding factors.'
)
add_justified_text(
    'First, the average teacher-to-student ratio in Nigerian public secondary schools ranges from '
    '1:40 to 1:100 depending on the region (National Bureau of Statistics, 2023), leaving teachers '
    'with limited time for individual lesson planning. Second, access to teaching resources and '
    'reference materials remains inadequate, particularly in rural schools. Third, the administrative '
    'burden on teachers extends beyond lesson preparation to include grading, record-keeping, and '
    'extracurricular responsibilities. These challenges collectively compromise the quality and '
    'consistency of lesson notes prepared by teachers.'
)
add_justified_text(
    'Recent advances in Artificial Intelligence (AI), particularly in the domain of Large Language '
    'Models (LLMs), have opened new possibilities for automating educational content generation. '
    'Models such as DeepSeek and Google\'s Gemini have demonstrated remarkable capabilities in '
    'generating coherent, contextually relevant, and pedagogically sound educational content. '
    'These technologies can be harnessed to create AI-powered tools that assist teachers in '
    'generating curriculum-aligned lesson notes efficiently and consistently.'
)
add_justified_text(
    'Despite the proliferation of AI educational tools globally, there remains a significant gap in '
    'solutions specifically designed for the Nigerian educational context. Most existing platforms '
    'cater to Western curricula (e.g., Common Core, Cambridge International) and lack awareness of '
    'the NERDC curriculum structure, Nigerian cultural context, and the unique technological constraints '
    '— such as unreliable internet connectivity and limited access to modern devices — prevalent in '
    'many Nigerian schools. This project addresses this gap by designing and developing ClassAI, an '
    'AI-powered lesson notes generator that is curriculum-aware, offline-first, and specifically '
    'optimised for Nigerian secondary schools.'
)

doc.add_heading('1.2 Statement of the Problem', level=2)
add_justified_text(
    'The preparation of standardised, high-quality lesson notes remains a persistent challenge in '
    'Nigerian secondary education. Teachers are expected to produce detailed lesson plans that align '
    'with NERDC curriculum specifications, incorporate appropriate pedagogical strategies, and address '
    'diverse learning needs. However, the following problems have been identified:'
)
add_bullet('Inadequate lesson planning time: Teachers manage heavy workloads with limited planning periods, resulting in rushed or incomplete lesson notes.')
add_bullet('Inconsistent content quality: The absence of standardised templates and quality assurance mechanisms leads to wide variation in lesson note quality across schools and teachers.')
add_bullet('Limited curriculum awareness: Many teachers, particularly those newly deployed or teaching multiple subjects, lack deep familiarity with curriculum specifications and expected learning outcomes.')
add_bullet('Technological constraints: Existing educational technology platforms require constant internet connectivity, which is unreliable and expensive in many parts of Nigeria.')
add_bullet('Absence of localised solutions: Most AI-powered educational tools are designed for Western educational systems and do not account for the NERDC curriculum structure, Nigerian cultural nuances, or locally relevant teaching resources.')
add_justified_text(
    'These problems collectively undermine the quality of instructional delivery and, consequently, '
    'student learning outcomes. There is a pressing need for an intelligent, context-aware, and '
    'offline-capable system that can assist Nigerian teachers in generating curriculum-aligned lesson '
    'notes efficiently and consistently.'
)

doc.add_heading('1.3 Aim and Objectives of the Study', level=2)
add_justified_text(
    'The aim of this project is to design and develop an AI-powered, curriculum-aware lesson notes '
    'generator (ClassAI) for Nigerian secondary schools. The specific objectives are to:'
)
add_bullet('Design a system architecture that integrates AI language models with NERDC curriculum specifications for automated lesson note generation.')
add_bullet('Develop a cross-platform mobile application using Flutter framework that implements offline-first capabilities, secure data storage with AES-256-GCM encryption, and resilient synchronisation mechanisms.')
add_bullet('Implement a dual-AI provider system with DeepSeek as the primary and Gemini as the fallback language model, ensuring continuous availability of content generation services.')
add_bullet('Build an academic calendar engine that provides term-aware week numbering aligned with the NERDC trimester schedule (First Term: September-December, Second Term: January-April, Third Term: April-July).')
add_bullet('Integrate a Paystack-based subscription payment system to support sustainable deployment across Nigerian schools.')
add_bullet('Align system features with findings from contemporary research on AI in education, including curriculum-informed AI, generative AI-powered educational alignment, and human-AI collaboration frameworks.')

doc.add_heading('1.4 Research Questions', level=2)
add_justified_text('The project is guided by the following research questions:')
add_bullet('How can a system architecture be designed to support curriculum-aware AI lesson note generation for the NERDC curriculum?')
add_bullet('What offline-first architectural patterns are most suitable for AI-powered educational tools operating in low-connectivity environments?')
add_bullet('How can a dual-provider AI system (DeepSeek with Gemini fallback) be implemented to ensure continuous content generation availability?')
add_bullet('How can features from contemporary AI education research be synthesised and implemented in a practical application for Nigerian secondary schools?')

doc.add_heading('1.5 Significance of the Study', level=2)
add_justified_text(
    'This project holds significant implications for various stakeholders in the Nigerian education sector:'
)
add_bullet('Teachers: The system provides a practical tool that reduces lesson planning time while maintaining content quality, enabling teachers to focus more on instructional delivery and student engagement.')
add_bullet('Students: Improved lesson note quality directly translates to better learning experiences and outcomes, as lessons are more structured, comprehensive, and aligned with curriculum objectives.')
add_bullet('School Administrators: Standardised lesson note generation facilitates quality assurance and supervision, allowing school leaders to monitor instructional quality more effectively.')
add_bullet('Researchers: The project contributes a practical implementation that synthesises findings from multiple AI education research papers into a working system.')
add_bullet('Policymakers: The system demonstrates how AI technologies can be leveraged for educational content generation in developing country contexts, informing future policy decisions.')

doc.add_heading('1.6 Scope and Delimitation', level=2)
add_justified_text(
    'This project focuses on the design and development of ClassAI as an AI-powered lesson notes '
    'generator. The scope covers: (1) integration with the NERDC curriculum for Nigerian secondary '
    'schools (JSS 1-3 and SSS 1-3), (2) support for 18 core subjects including English Studies, '
    'Mathematics, Basic Science, Social Studies, and Nigerian languages, (3) cross-platform deployment '
    'on Android, iOS, Web, and desktop platforms using Flutter, (4) offline-first operation with '
    'synchronisation capabilities, (5) AI-based generation using DeepSeek and Gemini language models '
    'with automatic failover, and (6) alignment of system features with findings from ten recent '
    'research papers on AI in education.'
)
add_justified_text(
    'The project does not cover primary or tertiary education institutions. The AI generation '
    'capabilities are constrained to the capabilities and limitations of the underlying LLM providers. '
    'The system\'s payment integration is limited to Paystack as the payment gateway. Empirical '
    'evaluation with teachers and students is outside the current scope, as the project is in the '
    'development phase.'
)

doc.add_heading('1.7 Organisation of the Report', level=2)
add_justified_text(
    'This report is organised into five chapters. Chapter 1 provides the introduction, background, '
    'problem statement, objectives, research questions, significance, and scope of the project. '
    'Chapter 2 presents a comprehensive review of ten recent research papers on AI in education, '
    'mapping their findings to features implemented in ClassAI. Chapter 3 describes the methodology, '
    'including the system architecture design, implementation approach, and technology stack. '
    'Chapter 4 presents the system implementation results and discusses how the features map to '
    'the research literature. Chapter 5 concludes the report with a summary, recommendations, '
    'contributions to knowledge, and suggestions for future work.'
)

doc.add_page_break()

# ═══════════════════════════════════════════════════════════════
# CHAPTER 2: LITERATURE REVIEW
# ═══════════════════════════════════════════════════════════════
doc.add_heading('CHAPTER 2', level=1)
doc.add_heading('LITERATURE REVIEW', level=1)

doc.add_heading('2.1 Review of Related Literature', level=2)

add_justified_text(
    'This chapter presents a comprehensive review of ten recent research papers on the application '
    'of Artificial Intelligence in education. Each paper is reviewed in terms of its key findings, '
    'methodology, and relevance to the design and development of ClassAI. The review is structured '
    'to highlight how findings from each study informed specific features and architectural decisions '
    'in the ClassAI system.'
)

# ── Paper 1 ──
doc.add_heading('2.1.1 Curriculum-Informed AI (Imagine Learning, 2025)', level=3)
add_justified_text(
    'The Imagine Learning white paper (2025) on Curriculum-Informed AI presents a comprehensive '
    'framework for integrating curriculum standards directly into AI model training and prompt '
    'engineering. The paper argues that for AI to be effective in educational settings, it must be '
    '"curriculum-informed" — meaning the AI system must have explicit awareness of curriculum '
    'standards, learning progressions, and grade-level expectations. The authors demonstrate that '
    'curriculum-informed AI significantly outperforms generic AI in generating content that is '
    'pedagogically appropriate and standards-aligned.'
)
add_justified_text(
    'Relevance to ClassAI: This paper directly influenced the design of ClassAI\'s prompt template '
    'system. The PromptTemplates class in ClassAI constructs detailed prompts that embed curriculum '
    'metadata — including subject, curriculum type (NERDC, Cambridge, CCSS), class level, week number, '
    'topic, difficulty level, and Bloom\'s Taxonomy verbs. This ensures that the AI generation is '
    'explicitly guided by curriculum specifications. The system also implements the curriculum type '
    'enumeration (CurriculumType enum in curriculum_types.dart) that supports three curricula with '
    'version tracking, mirroring the curriculum-informed approach advocated by Imagine Learning.'
)

# ── Paper 2 ──
doc.add_heading('2.1.2 Generative AI-Powered Educational Alignment (Liu, Mendoza, Martin & Miori, 2024/2026)', level=3)
add_justified_text(
    'Liu, Mendoza, Martin, and Miori (2024) presented their work at ACM ICDEL 2024 on generative '
    'AI-powered educational alignment. Their research investigates how generative AI models can be '
    'used to automatically align educational content with predefined learning standards and objectives. '
    'The study proposes a framework that uses LLMs to map content to standard learning outcomes, '
    'identify gaps in coverage, and suggest remediation. The authors demonstrated that their approach '
    'achieved 85% alignment accuracy when tested against human expert evaluations.'
)
add_justified_text(
    'Relevance to ClassAI: This paper informed the design of ClassAI\'s content structure for lesson '
    'notes. The system\'s JSON output schema — which includes structured fields for learning objectives, '
    'key vocabulary, materials, lesson presentation, assessment, and homework — was designed to ensure '
    'that generated content covers all essential pedagogical components. The alignment verification '
    'logic in the merge engine (MergeEngine class) provides field-level conflict detection that can '
    'be extended to verify curriculum alignment. The curriculum type enumeration with version tracking '
    '(nerdc_v2024, cambridge_v2025, ccss_v2024) supports the version-aware alignment discussed in '
    'this paper.'
)

# ── Paper 3 ──
doc.add_heading('2.1.3 Artificial Intelligence in Curriculum Development (Mohamed Sapawi & Nik Yusoff, 2025)', level=3)
add_justified_text(
    'Mohamed Sapawi and Nik Yusoff (2025) published a study in the Journal of Curriculum Studies '
    'Research examining the role of artificial intelligence in curriculum development processes. '
    'Their research explores how AI can assist in curriculum mapping, content sequencing, and the '
    'identification of prerequisite knowledge structures. The authors argue that AI can enhance '
    'curriculum development by analysing large volumes of curriculum data to identify patterns, '
    'gaps, and optimal learning progressions. They also discuss the importance of human oversight '
    'in AI-assisted curriculum development, emphasising that AI should augment rather than replace '
    'human curriculum expertise.'
)
add_justified_text(
    'Relevance to ClassAI: This paper informed the system\'s approach to academic calendar management '
    'and scheme of work generation. The AcademicCalendarService implements NERDC trimester-aware week '
    'numbering, providing the curriculum context needed for topic scheduling. The scheme_of_work '
    'database table stores topic sequences per term, enabling the system to understand curriculum '
    'progression. The emphasis on human oversight is reflected in ClassAI\'s design philosophy — the '
    'system generates draft content that teachers review, customise, and approve, preserving teacher '
    'professional judgment.'
)

# ── Paper 4 ──
doc.add_heading('2.1.4 Exploring the Impact of Generative AI on Curriculum Design and Instruction (Preservice Teachers Study, 2026)', level=3)
add_justified_text(
    'A 2026 study published on ResearchGate explored the impact of generative AI on curriculum design '
    'and instruction through a study with preservice teachers. The research investigated how '
    'teacher-trainees interact with generative AI tools for lesson planning and how these tools '
    'influence their understanding of curriculum design principles. The findings revealed that '
    'preservice teachers who used AI-assisted planning tools demonstrated improved understanding '
    'of curriculum alignment, but also showed tendencies to over-rely on AI-generated content '
    'without critical evaluation. The study recommends that AI tools in education should be designed '
    'to encourage active teacher engagement rather than passive acceptance of generated content.'
)
add_justified_text(
    'Relevance to ClassAI: This paper influenced the interactive design of ClassAI\'s lesson editor '
    'screen. The system requires teachers to actively input parameters such as subject, topic, '
    'difficulty level, and Bloom\'s Taxonomy verbs before generation. The generated content is '
    'presented in an editable format, allowing teachers to modify, add, or remove sections. The '
    'lesson_editor_screen.dart and lessons_list_screen.dart implement this interactive workflow, '
    'encouraging the active teacher engagement recommended by this study.'
)

# ── Paper 5 ──
doc.add_heading('2.1.5 AI-Assisted Lesson Generation in Professional Education (Wiley Practical Guide, 2026)', level=3)
add_justified_text(
    'A practical guide published by Wiley (2026) on AI-assisted lesson generation in medical and '
    'professional education provides structured methodologies for incorporating AI into lesson '
    'design workflows. The guide outlines a step-by-step process: (1) define learning objectives, '
    '(2) specify content parameters, (3) generate initial content with AI, (4) review and refine, '
    '(5) add assessment components, and (6) finalise for delivery. The guide emphasises the '
    'importance of structured prompts, clear output specifications, and iterative refinement '
    'cycles for achieving high-quality AI-generated educational content.'
)
add_justified_text(
    'Relevance to ClassAI: This guide\'s six-step workflow maps directly to ClassAI\'s lesson '
    'generation pipeline. The system implements this through: (1) the PromptTemplates class '
    'defining structured prompts with explicit learning objective requirements, (2) the subject, '
    'class level, week, and topic input fields on the lesson editor, (3) the AiService.generate() '
    'method with injection detection and token management, (4) the editable output interface where '
    'teachers review generated content, (5) the assessment section automatically included in the '
    'structured JSON output, and (6) the PDF and CSV export services for final content delivery. '
    'The dual-provider failover mechanism (DeepSeek to Gemini) ensures reliability in the '
    'generation step.'
)

# ── Paper 6 ──
doc.add_heading('2.1.6 Enhancing E-Learning Through AI (Mahafdah, Bouallegue & Bouallegue, 2024)', level=3)
add_justified_text(
    'Mahafdah, Bouallegue, and Bouallegue (2024) published a study in PeerJ Computer Science '
    'examining the enhancement of e-learning through artificial intelligence. Their research '
    'explored various AI techniques — including natural language processing, machine learning, '
    'and recommendation systems — for improving online learning experiences. The study identified '
    'key success factors for AI in e-learning: personalisation of content, adaptive assessment, '
    'real-time feedback, and intelligent content recommendation. The authors also highlighted '
    'the importance of data security and privacy in AI-powered educational systems.'
)
add_justified_text(
    'Relevance to ClassAI: This paper informed several security and content management features. '
    'The AES-256-GCM encryption implementation (encryption_utils.dart) addresses the data security '
    'concerns raised in the study. The vault system (vault_browser_screen.dart, vault_item_detail_'
    'screen.dart, vault_publisher_screen.dart) provides secure storage and controlled publishing of '
    'educational content. The credit system (credit_service.dart) implements intelligent access '
    'control, ensuring that content generation resources are allocated appropriately based on '
    'subscription tier.'
)

# ── Paper 7 ──
doc.add_heading('2.1.7 Assessing the Impact of AI-Generated Personalised Lesson Plans (arxiv, 2025)', level=3)
add_justified_text(
    'An arxiv paper (2025) on assessing the impact of AI-generated personalised lesson plans '
    'presented a framework for evaluating AI-generated educational content. The study proposed '
    'evaluation criteria including content accuracy, pedagogical appropriateness, curriculum '
    'alignment, language quality, and completeness. The authors developed a rubric-based assessment '
    'methodology that combines automated evaluation metrics with human expert review. Their findings '
    'indicated that AI-generated lesson plans, when properly prompted, achieved comparable quality '
    'ratings to human-created plans in terms of structure and curriculum alignment, though they '
    'sometimes lacked contextual nuance.'
)
add_justified_text(
    'Relevance to ClassAI: The evaluation framework from this paper influenced the design of '
    'ClassAI\'s content quality assurance mechanisms. The audit_logs database table stores '
    'generation metadata including teacher ID, school ID, topic, and timestamp, enabling quality '
    'tracking. The content validation logic in AiService, including markdown stripping and JSON '
    'parsing (_stripMarkdownWrappers method), ensures that generated content conforms to the '
    'expected structured format. The sanitisation utilities (sanitization_utils.dart) implement '
    'injection detection, contributing to content safety and quality.'
)

# ── Paper 8 ──
doc.add_heading('2.1.8 Designing and Evaluating an AI-Integrated Curriculum (NCBI PMC, 2025)', level=3)
add_justified_text(
    'A 2025 study published via NCBI PMC examined the co-design and evaluation of AI-integrated '
    'curriculum assessment systems. The research focused on how AI can be integrated into existing '
    'curriculum frameworks through a participatory design approach involving teachers, curriculum '
    'developers, and AI specialists. The study found that successful AI integration requires: '
    '(1) alignment with existing curriculum structures, (2) teacher involvement in the design '
    'process, (3) transparent AI decision-making, and (4) robust feedback mechanisms for continuous '
    'improvement.'
)
add_justified_text(
    'Relevance to ClassAI: This paper\'s participatory design principles are reflected in ClassAI\'s '
    'architecture. The system provides teachers with full control over generation parameters, '
    'allowing them to specify subject, class level, week, topic, difficulty, and Bloom\'s Taxonomy '
    'levels. The editable lesson output ensures teacher agency in the final content. The audit '
    'logging system provides transparency by recording all generation events. The merge engine '
    '(merge_engine.dart and merge_strategies.dart) with field-level conflict resolution supports '
    'collaborative content workflows where multiple teachers can contribute to content refinement.'
)

# ── Paper 9 ──
doc.add_heading('2.1.9 Learning Design to Advance Human-AI Collaboration in K-12 Education (Chan, Kim et al., ODU)', level=3)
add_justified_text(
    'Chan, Kim, and colleagues published a study through Old Dominion University\'s Digital Commons '
    'examining learning design frameworks for advancing human-AI collaboration in K-12 education. '
    'The research proposes a "Human-AI Collaboration Framework" that identifies three collaboration '
    'modes: (1) AI as assistant — handling routine tasks while humans focus on complex decisions, '
    '(2) AI as augmenter — enhancing human capabilities with AI-generated insights, and '
    '(3) AI as explorer — discovering new patterns and possibilities that humans may not have '
    'considered. The study emphasises that educational AI should be designed to complement rather '
    'than replace teacher expertise.'
)
add_justified_text(
    'Relevance to ClassAI: This framework directly shaped ClassAI\'s design philosophy. ClassAI '
    'operates primarily in the "AI as assistant" mode — handling the routine task of generating '
    'structured, curriculum-aligned lesson content from teacher-provided parameters. It also '
    'functions in "AI as augmenter" mode by suggesting Bloom\'s Taxonomy-aligned cognitive levels, '
    'vocabulary lists, and assessment strategies that teachers may not have considered. The system '
    'is explicitly designed as a teacher assistance tool, with the teacher remaining the final '
    'decision-maker on content appropriateness. The human-AI collaboration is embedded in the '
    'workflow: teachers specify parameters, AI generates content, and teachers review, customise, '
    'and approve the output.'
)

# ── Paper 10 ──
doc.add_heading('2.1.10 Use of Generative AI in Writing Lesson Plans (Del Valle, 2025)', level=3)
add_justified_text(
    'Del Valle (2025) published a study in the International Journal of Social Science and Humanities '
    'Research (IJSSHMR) on the use of generative AI in writing lesson plans. The research surveyed '
    'teachers\' experiences with generative AI tools for lesson planning, examining benefits, '
    'challenges, and best practices. Key findings included: (1) teachers reported significant time '
    'savings (averaging 30-45 minutes per lesson plan), (2) AI-generated content was perceived as '
    'well-structured but requiring contextual customisation, (3) teachers valued the ability to '
    'specify grade level and subject parameters, and (4) the most successful implementations were '
    'those where AI handled structure and baseline content while teachers focused on customisation '
    'and contextualisation.'
)
add_justified_text(
    'Relevance to ClassAI: Del Valle\'s findings validate several design decisions in ClassAI. '
    'The system\'s structured lesson note format — with clearly delineated sections for objectives, '
    'vocabulary, materials, presentation, assessment, and homework — addresses the teacher preference '
    'for well-structured AI output. The parameter specification interface (subject, class level, '
    'week, topic, difficulty) implements the teacher-input-driven approach recommended in the study. '
    'The export functionality (export_service.dart) supporting both CSV and PDF formats facilitates '
    'the customisation workflow, allowing teachers to export, modify, and finalise content in their '
    'preferred format.'
)

doc.add_heading('2.2 Theoretical Framework', level=2)

doc.add_heading('2.2.1 Constructivist Learning Theory', level=3)
add_justified_text(
    'Constructivist learning theory, rooted in the works of Piaget (1972) and Vygotsky (1978), posits '
    'that learners actively construct knowledge through interaction with their environment and social '
    'context. This theory emphasises the importance of meaningful, contextually relevant learning '
    'experiences that build upon existing knowledge structures. In the context of lesson note generation, '
    'constructivism suggests that effective lesson plans should incorporate activities that promote '
    'active learning, critical thinking, and knowledge construction rather than passive information '
    'transmission.'
)
add_justified_text(
    'ClassAI\'s lesson note generation is grounded in constructivist principles. The generated lesson '
    'notes include structured presentation sections that guide teachers through activity-based learning '
    'sequences, incorporating starter activities, main activities, and plenary sessions. The assessment '
    'components are designed to evaluate higher-order thinking skills aligned with constructivist '
    'pedagogy, moving beyond simple recall to application, analysis, and evaluation tasks.'
)

doc.add_heading('2.2.2 Technological Pedagogical Content Knowledge (TPACK)', level=3)
add_justified_text(
    'The Technological Pedagogical Content Knowledge (TPACK) framework, developed by Mishra and '
    'Koehler (2006), describes the types of knowledge teachers need to effectively integrate technology '
    'into their teaching practice. TPACK identifies three primary knowledge domains — Content Knowledge '
    '(CK), Pedagogical Knowledge (PK), and Technological Knowledge (TK) — and their intersections.'
)
add_justified_text(
    'ClassAI embodies the TPACK framework by providing an AI-powered tool that bridges the gap between '
    'content knowledge (curriculum specifications and subject matter), pedagogical knowledge (teaching '
    'strategies, assessment design, and cognitive level targeting), and technological knowledge '
    '(cross-platform mobile application, AI generation, offline capabilities). The system reduces '
    'the technological burden on teachers by automating complex tasks while preserving their '
    'professional autonomy in customising and delivering the generated content.'
)

doc.add_heading('2.3 Summary of Literature Review', level=2)
add_justified_text(
    'The ten research papers reviewed in this chapter provide a comprehensive foundation for the '
    'design and development of ClassAI. The literature reveals several key themes that have directly '
    'influenced the system architecture:'
)
add_bullet('Curriculum Awareness: Multiple studies (Imagine Learning, 2025; Liu et al., 2024; Mohamed Sapawi & Nik Yusoff, 2025) emphasise the importance of AI systems being explicitly aware of curriculum standards. ClassAI addresses this through its prompt template system that embeds curriculum metadata and its multi-curriculum support (NERDC, Cambridge, CCSS).')
add_bullet('Human-AI Collaboration: The Human-AI Collaboration Framework (Chan, Kim et al.) and the preservice teachers study (2026) both stress that AI should augment rather than replace teacher expertise. ClassAI implements this through its interactive generation workflow where teachers specify parameters, review output, and customise content.')
add_bullet('Structured Content Generation: The Wiley practical guide (2026) and Del Valle (2025) demonstrate the importance of structured, well-formatted AI output. ClassAI\'s JSON schema with explicit sections for objectives, vocabulary, materials, presentation, assessment, and homework addresses this requirement.')
add_bullet('Security and Privacy: Mahafdah et al. (2024) highlight data security concerns in AI-powered educational systems. ClassAI implements AES-256-GCM encryption, Argon2id key derivation, and secure local storage to address these concerns.')
add_bullet('Quality Assurance: The arxiv paper (2025) on personalised lesson plan assessment provides evaluation criteria that have informed ClassAI\'s content validation and audit logging mechanisms.')
add_bullet('Offline Capability: While not explicitly discussed in the reviewed papers, the practical requirements of the Nigerian educational context demand offline-first architecture, which ClassAI implements through its local SQLite database, credit system, and synchronisation engine.')

doc.add_page_break()

# ═══════════════════════════════════════════════════════════════
# CHAPTER 3: METHODOLOGY
# ═══════════════════════════════════════════════════════════════
doc.add_heading('CHAPTER 3', level=1)
doc.add_heading('METHODOLOGY', level=1)

doc.add_heading('3.1 Research Design', level=2)
add_justified_text(
    'This project adopted a Design Science Research (DSR) methodology, which is a well-established '
    'research paradigm in computer science and information systems that focuses on the development '
    'and evaluation of innovative artefacts to solve identified problems. The DSR approach was '
    'selected because it accommodates both the technical development of the ClassAI system (the '
    'artefact) and the systematic review of research literature that informs the design.'
)
add_justified_text(
    'The project followed Peffers et al.\'s (2007) six-step DSR process: (1) problem identification '
    'and motivation — identifying the challenge of lesson note preparation in Nigerian secondary '
    'schools; (2) definition of solution objectives — specifying the requirements for an AI-powered '
    'lesson notes generator; (3) design and development — building the ClassAI system using Flutter '
    'and Dart; (4) demonstration — showing how the system generates curriculum-aligned lesson notes; '
    '(5) evaluation — mapping system features to findings from research literature; and '
    '(6) communication — documenting the system design, implementation, and findings in this report.'
)

doc.add_heading('3.2 System Architecture and Design', level=2)

doc.add_heading('3.2.1 Overall Architecture', level=3)
add_justified_text(
    'ClassAI adopts a three-tier architecture consisting of a presentation tier (Flutter cross-platform '
    'UI), a logic tier (Dart services and providers), and a data tier (local SQLite database and '
    'Supabase cloud backend). This architecture ensures separation of concerns, maintainability, and '
    'the ability to operate independently of network connectivity.'
)
add_justified_text(
    'The presentation layer is built using Flutter\'s widget-based UI framework with Riverpod for '
    'state management (flutter_riverpod: ^3.3.1). Key screens include the Dashboard, Lesson Editor, '
    'Exam Editor, Scheme of Work, Settings, Admin Dashboard, Payment, and Vault. The router is '
    'implemented using go_router (^17.2.3) for declarative routing with deep link support '
    '(via app_links: ^6.3.2).'
)
add_justified_text(
    'The logic tier comprises service classes that encapsulate business logic: AiService for prompt '
    'construction and LLM communication, SyncService for data synchronisation, AcademicCalendarService '
    'for term-aware week calculations, CreditService for subscription management, PaymentService for '
    'Paystack integration, ExportService for data export to CSV/PDF, SecurityService for encryption '
    'and authentication operations, VacuumService for safe database maintenance, PdfService for PDF '
    'generation with caching, and MergeEngine for three-way data conflict resolution.'
)
add_justified_text(
    'The data tier uses Drift ORM (^2.31.0) for local SQLite database management with 20 database '
    'tables covering lessons, subjects, teachers, schools, terms, schemes of work, exams, sync '
    'queue, audit logs, and security configurations. Supabase (supabase_flutter: ^2.12.4) provides '
    'the cloud PostgreSQL database, real-time subscriptions, and authentication services.'
)

doc.add_heading('3.2.2 AI Generation Workflow', level=3)
add_justified_text(
    'The AI generation workflow in ClassAI follows a structured pipeline informed by the curriculum-'
    'informed AI approach advocated by Imagine Learning (2025) and the generative AI alignment '
    'framework by Liu et al. (2024):'
)
add_bullet('Prompt Construction: The system constructs a detailed prompt using the PromptTemplates class, incorporating subject, curriculum type, class level, week number, topic, difficulty level, and Bloom\'s Taxonomy verbs specified by the teacher.')
add_bullet('Injection Detection: The constructed prompt is scanned for prompt injection attempts using SanitizationUtils.findInjections(), which detects SQL injection patterns, system prompt override attempts, and other malicious inputs.')
add_bullet('Token Management: The prompt is truncated if it exceeds 4,096 tokens using TokenCounter.truncateIfNeeded(), ensuring it fits within the LLM\'s context window while preserving essential curriculum metadata.')
add_bullet('Primary Generation: The system sends the sanitised prompt to the DeepSeek API. If successful, the response is parsed and returned.')
add_bullet('Automatic Failover: If DeepSeek API returns an error (network failure, rate limiting, service outage), the system automatically retries the request using the Gemini API, ensuring continuous service availability.')
add_bullet('Response Parsing: The AI response is stripped of markdown wrappers (code fences, introductory/concluding text) and parsed as JSON. The structured output includes learning objectives, key vocabulary, materials, lesson presentation, assessment, and homework sections.')
add_bullet('Audit Logging: Each generation event is logged with teacher ID, school ID, topic, and timestamp for accountability and usage tracking.')

doc.add_heading('3.2.3 Offline-First Synchronisation Pipeline', level=3)
add_justified_text(
    'ClassAI\'s synchronisation pipeline implements a robust offline-first strategy designed for '
    'the intermittent connectivity typical of Nigerian schools. The SyncService manages the full '
    'sync lifecycle through a state machine with the following states: idle, acquiringSession, '
    'biometricPrompt, sessionKeyDecrypt, pulling, merging, savingConflicts, pushing, applyingCredits, '
    'emergencySave, forcedLogout, updatingMetadata, replayingRealtime, and backoff.'
)
add_justified_text(
    'The sync system implements exponential backoff for retries (starting at 5 seconds, doubling up '
    'to 5 retries), payload compression for transfers exceeding 50 KB, and batch-size reduction '
    '(from 10 to 5 records per batch) optimised for 2G/3G network conditions. The MergeEngine '
    'supports three-way merging (local, remote, base) with configurable field-level strategies '
    'including Last-Writer-Wins (LWW), union, keep local, keep remote, and manual resolution.'
)

doc.add_heading('3.2.4 Database Schema', level=3)
add_justified_text(
    'The ClassAI database schema comprises 20 tables designed to support all system functionalities:'
)
add_bullet('lessons — Stores generated lesson notes with encrypted content, subject, class level, week, topic, difficulty, curriculum type, Bloom\'s Taxonomy verbs, and status (draft/published/archived).')
add_bullet('subjects — Defines available subjects per curriculum with 18 NERDC core subjects pre-configured.')
add_bullet('teachers — Teacher profiles with authentication data, device registration, and token management.')
add_bullet('schools — School information, subscription tier, expiry date, and configuration settings.')
add_bullet('terms — Academic term definitions with start/end dates, term names, and school association.')
add_bullet('scheme_of_work — Schedule of topics per term with week-by-week planning.')
add_bullet('exams — Generated examination questions with MCQ, theory, and subjective question types.')
add_bullet('exams_dao, lessons_dao, subjects_dao, teachers_dao, schools_dao, terms_dao, scheme_of_work_dao — Data Access Objects for database operations.')
add_bullet('sync_queue — Pending synchronisation entries with retry tracking and conflict resolution.')
add_bullet('audit_logs — Security and usage audit trail for accountability.')
add_bullet('security_config — Encryption keys, credit balances, daily generation counters.')
add_bullet('vault_items — Encrypted sensitive data storage for secure content publishing.')
add_bullet('payment_events — Transaction records for Paystack payment tracking.')
add_bullet('pdf_cache — Cached PDF generation outputs for performance optimisation.')
add_bullet('teacher_devices — Registered device tracking for multi-device sync.')
add_bullet('teacher_subjects — Subject assignment mapping for teachers.')
add_bullet('conflicts — Unresolved sync conflicts requiring manual resolution.')
add_bullet('progress_logs — Teacher progress tracking across curriculum topics.')
add_bullet('pending_recovery_requests — Password recovery workflow management.')
add_bullet('recovery_codes — One-time recovery codes for account access restoration.')

doc.add_heading('3.2.5 Security Architecture', level=3)
add_justified_text(
    'ClassAI implements a multi-layered security architecture: (1) AES-256-GCM encryption using the '
    'cryptography Dart package (^2.9.0) for lesson content at rest; (2) Argon2id key derivation '
    'function with configurable memory (32,768 KB), iterations (3), and parallelism (2) parameters; '
    '(3) Flutter Secure Storage (flutter_secure_storage: ^10.2.0) for protecting sensitive tokens; '
    '(4) biometric authentication via local_auth (^3.0.1) for accessing encrypted content; '
    '(5) session management with token refresh and token_version_mismatch detection for identifying '
    'logins on other devices; and (6) Sentry integration (sentry_flutter: ^8.14.2) for error monitoring '
    'and crash reporting.'
)

doc.add_heading('3.3 Implementation Details', level=2)

doc.add_heading('3.3.1 Development Environment', level=3)
add_justified_text(
    'The system was developed using the Flutter SDK (version 3.4.0) with Dart programming language. '
    'The minimum target SDK for Android is API 21 (Android 5.0), and the minimum iOS deployment '
    'target is iOS 12.0. Build automation was managed through Gradle (Android) and CocoaPods (iOS). '
    'The project also includes web and desktop (Linux, macOS, Windows) platform support through '
    'Flutter\'s multi-platform compilation.'
)

doc.add_heading('3.3.2 Key Dependencies', level=3)
add_justified_text('The following key dependencies were used in the project implementation:')

# Dependencies table
table = doc.add_table(rows=1, cols=3)
table.style = 'Table Grid'
table.alignment = WD_TABLE_ALIGNMENT.CENTER
hdr = table.rows[0]
for i, text in enumerate(['Package', 'Version', 'Purpose']):
    cell = hdr.cells[i]
    cell.text = ''
    p = cell.paragraphs[0]
    run = p.add_run(text)
    run.font.name = 'Times New Roman'
    run.font.size = Pt(11)
    run.bold = True
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    shading = parse_xml(f'<w:shd {nsdecls("w")} w:fill="D9E2F3"/>')
    cell._tc.get_or_add_tcPr().append(shading)

deps = [
    ('flutter_riverpod', '3.3.1', 'State management'),
    ('drift', '2.31.0', 'Local SQLite ORM'),
    ('supabase_flutter', '2.12.4', 'Cloud backend & auth'),
    ('flutter_secure_storage', '10.2.0', 'Secure token storage'),
    ('cryptography', '2.9.0', 'AES-256-GCM & Argon2id'),
    ('dio', '5.9.2', 'HTTP client for APIs'),
    ('pdf', '3.12.0', 'PDF document generation'),
    ('go_router', '17.2.3', 'Declarative routing'),
    ('sentry_flutter', '8.14.2', 'Error monitoring'),
    ('local_auth', '3.0.1', 'Biometric authentication'),
    ('connectivity_plus', '7.1.1', 'Network status detection'),
    ('intl', '0.20.2', 'Internationalisation'),
    ('uuid', '4.5.3', 'Unique ID generation'),
    ('flutter_image_compress', '2.4.0', 'Image optimisation'),
    ('image_picker', '1.2.2', 'Camera/gallery access'),
]
for row_data in deps:
    add_table_row(table, row_data)

doc.add_paragraph()

doc.add_heading('3.3.3 Project Structure', level=3)
add_justified_text(
    'The ClassAI project follows a feature-first directory structure under the lib/ directory:'
)
add_bullet('core/ — Shared code including constants, database (tables, DAOs), services, providers, theme, utilities, and widgets.')
add_bullet('features/ — Feature-specific code organised by domain: admin, auth, credit, dashboard, exam, lesson, payment, scheme_of_work, settings, and vault.')
add_bullet('router/ — Application routing configuration using go_router with authentication guards.')
add_bullet('test/ — Unit and widget tests covering AI services, authentication, sync, encryption, credits, UI components, and database operations (30+ test files).')

doc.add_heading('3.4 Technology Stack', level=2)
add_justified_text(
    'The technology stack for ClassAI was selected based on requirements for cross-platform deployment, '
    'offline capability, security, and AI integration:'
)

# Tech stack table
table2 = doc.add_table(rows=1, cols=3)
table2.style = 'Table Grid'
table2.alignment = WD_TABLE_ALIGNMENT.CENTER
hdr2 = table2.rows[0]
for i, text in enumerate(['Component', 'Technology', 'Version']):
    cell = hdr2.cells[i]
    cell.text = ''
    p = cell.paragraphs[0]
    run = p.add_run(text)
    run.font.name = 'Times New Roman'
    run.font.size = Pt(11)
    run.bold = True
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    shading = parse_xml(f'<w:shd {nsdecls("w")} w:fill="D9E2F3"/>')
    cell._tc.get_or_add_tcPr().append(shading)

tech_stack = [
    ('Framework', 'Flutter (Dart)', '>=3.4.0'),
    ('State Management', 'Riverpod', '3.3.1'),
    ('Local Database', 'SQLite (Drift ORM)', '2.31.0'),
    ('Cloud Backend', 'Supabase (PostgreSQL)', '2.12.4'),
    ('AI Provider (Primary)', 'DeepSeek API', 'Latest'),
    ('AI Provider (Fallback)', 'Gemini API', 'Latest'),
    ('Encryption', 'AES-256-GCM / Argon2id', '2.9.0'),
    ('Payment Gateway', 'Paystack API', 'Latest'),
    ('HTTP Client', 'Dio', '5.9.2'),
    ('PDF Generation', 'pdf package', '3.12.0'),
    ('Error Monitoring', 'Sentry', '8.14.2'),
    ('Routing', 'go_router', '17.2.3'),
    ('Biometrics', 'local_auth', '3.0.1'),
]
for row_data in tech_stack:
    add_table_row(table2, row_data)

doc.add_page_break()

# ═══════════════════════════════════════════════════════════════
# CHAPTER 4: SYSTEM DEVELOPMENT AND RESULTS
# ═══════════════════════════════════════════════════════════════
doc.add_heading('CHAPTER 4', level=1)
doc.add_heading('SYSTEM DEVELOPMENT AND RESULTS', level=1)

doc.add_heading('4.1 System Implementation Results', level=2)

doc.add_heading('4.1.1 Functional Modules Implementation', level=3)
add_justified_text(
    'The ClassAI system has been successfully implemented with all planned functional modules '
    'operational. The application compiles and runs on Android, iOS, Web, and desktop platforms '
    '(Linux, macOS, Windows) with a single Dart codebase, demonstrating the effectiveness of '
    'Flutter\'s cross-platform capabilities. The following subsections present the implementation '
    'status of each major module.'
)

add_justified_text(
    'Authentication Module: The auth system supports email/password registration and login with '
    'Supabase authentication, email verification, password reset with recovery codes, SMS OTP '
    'verification (via Termii API), biometric authentication integration, and session management '
    'with token refresh. The module also implements login on other device detection '
    '(token_version_mismatch) and automatic logout on security violations. The implementation is '
    'located in auth_service.dart (1,043 lines) covering login, signup, password recovery, '
    'email verification, and admin recovery workflows.'
)

add_justified_text(
    'Lesson Generation Module: The AI-powered lesson generation system successfully generates '
    'structured lesson notes through the curriculum-informed prompt pipeline. The PromptTemplates '
    'class constructs prompts incorporating subject, curriculum type, class level, week number, '
    'topic, difficulty, and Bloom\'s Taxonomy verbs. The AiService class (164 lines) manages the '
    'full generation lifecycle including injection detection, token truncation, DeepSeek primary '
    'call, Gemini fallback, markdown stripping, and JSON parsing. The system supports all three '
    'supported curricula (NERDC, Cambridge, CCSS) with appropriate prompt customisation.'
)

add_justified_text(
    'Academic Calendar Engine: The AcademicCalendarService (152 lines) implements NERDC trimester-aware '
    'week numbering. The system recognises the standard Nigerian academic calendar: First Term '
    '(September-December), Second Term (January-April), and Third Term (April-July). Week numbering '
    'resets at the start of each term (Week 1). The service also calculates academic years using the '
    'September-August cycle typical of Nigerian schools.'
)

add_justified_text(
    'Offline Credit System: The credit system implements the specified offline credit allocation '
    'per subscription tier: Free (3 credits), Basic (5 credits), Standard (10 credits), and Elite '
    '(20 credits). Credit deduction follows the "batch-write-before-network" pattern where the batch '
    'ID is written to SQLite before any network call, ensuring atomicity and preventing double-spending. '
    'The CreditService (97 lines) handles credit spending, offline deduction, and sync queue management.'
)

add_justified_text(
    'Data Export Module: The ExportService (135 lines) supports export of lesson data in CSV format '
    'with columns: Title, Week, Topic, Objectives, Materials, Assessment, and Created. The PdfService '
    '(236 lines) handles PDF generation with caching (via pdf_cache database table), watermarking '
    'for free-tier users, and low-storage protection that blocks generation when storage falls below '
    '100 MB critical threshold.'
)

add_justified_text(
    'Payment Integration: The PaymentService (182 lines) integrates with the Paystack API for '
    'subscription management. It supports payment initialisation with checkout URL generation, '
    'payment confirmation via webhook or polling, activation code generation, and subscription '
    'tier management. The pricing structure supports four tiers with annual billing in Nigerian '
    'Naira: Basic (NGN 49,999/year), Standard (NGN 99,999/year), and Elite (NGN 249,999/year).'
)

add_justified_text(
    'Database and Synchronisation: The SyncService (1,530 lines) implements the comprehensive '
    'offline-first synchronisation engine. It manages session acquisition, biometric authentication '
    'for key decryption, data pulling and pushing, three-way merging via MergeEngine (195 lines), '
    'and conflict storage for manual resolution. The system supports payload compression, batch '
    'size optimisation for 2G/3G networks, and exponential backoff for retry management.'
)

doc.add_heading('4.1.2 System Configuration and Requirements', level=3)
add_justified_text(
    'The system\'s minimum hardware and software requirements are as follows:'
)

# Config table
table3 = doc.add_table(rows=1, cols=2)
table3.style = 'Table Grid'
table3.alignment = WD_TABLE_ALIGNMENT.CENTER
hdr3 = table3.rows[0]
for i, text in enumerate(['Requirement', 'Specification']):
    cell = hdr3.cells[i]
    cell.text = ''
    p = cell.paragraphs[0]
    run = p.add_run(text)
    run.font.name = 'Times New Roman'
    run.font.size = Pt(11)
    run.bold = True
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    shading = parse_xml(f'<w:shd {nsdecls("w")} w:fill="D9E2F3"/>')
    cell._tc.get_or_add_tcPr().append(shading)

config_data = [
    ('Minimum Android Version', 'API 21 (Android 5.0)'),
    ('Minimum iOS Version', 'iOS 12.0'),
    ('Minimum RAM', '3 GB'),
    ('Minimum Storage', '500 MB free space'),
    ('Internet Requirement', 'Not required for core functions (offline-first)'),
    ('AI API Key Required', 'For school administrator/setup'),
    ('Screen Size Support', 'Mobile and Tablet (minimum 600dp width for tablet mode)'),
    ('Biometric Support', 'Fingerprint or Face ID (optional)'),
    ('Target Platforms', 'Android, iOS, Web, Linux, macOS, Windows'),
]
for row_data in config_data:
    add_table_row(table3, row_data)

doc.add_paragraph()

doc.add_heading('4.2 Feature Mapping to Research Literature', level=2)

add_justified_text(
    'Table 4.1 below summarises how specific features implemented in ClassAI map to findings '
    'and recommendations from the ten research papers reviewed in Chapter 2.'
)

# Feature mapping table
table4 = doc.add_table(rows=1, cols=3)
table4.style = 'Table Grid'
table4.alignment = WD_TABLE_ALIGNMENT.CENTER
hdr4 = table4.rows[0]
for i, text in enumerate(['Feature', 'Research Paper', 'Mapping Description']):
    cell = hdr4.cells[i]
    cell.text = ''
    p = cell.paragraphs[0]
    run = p.add_run(text)
    run.font.name = 'Times New Roman'
    run.font.size = Pt(10)
    run.bold = True
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    shading = parse_xml(f'<w:shd {nsdecls("w")} w:fill="D9E2F3"/>')
    cell._tc.get_or_add_tcPr().append(shading)

mapping_data = [
    ('Curriculum-aware prompt templates',
     'Imagine Learning (2025)',
     'Curriculum-Informed AI framework — embedding curriculum metadata directly into prompts'),
    ('Multi-curriculum support (NERDC, Cambridge, CCSS)',
     'Liu, Mendoza, Martin & Miori (2024)',
     'Generative AI-powered educational alignment across multiple standards'),
    ('Academic calendar engine with trimester awareness',
     'Mohamed Sapawi & Nik Yusoff (2025)',
     'AI in curriculum development — content sequencing and progression'),
    ('Interactive lesson editor for teacher customisation',
     'Preservice Teachers Study (2026)',
     'Preventing over-reliance — encouraging active teacher engagement'),
    ('Structured lesson note sections (objectives, vocabulary, presentation, assessment, homework)',
     'Wiley Practical Guide (2026)',
     'Six-step AI-assisted lesson generation workflow'),
    ('AES-256-GCM encryption for content at rest',
     'Mahafdah, Bouallegue & Bouallegue (2024)',
     'Data security and privacy in AI-powered e-learning systems'),
    ('Audit logging and generation metadata tracking',
     'arxiv AI Lesson Plan Assessment (2025)',
     'Quality assessment framework — evaluation criteria for AI-generated content'),
    ('Teacher parameter control (subject, level, week, topic, difficulty, Bloom\'s verbs)',
     'NCBI PMC AI-Integrated Curriculum (2025)',
     'Participatory design — teacher involvement in AI content generation'),
    ('Human-AI collaborative workflow (AI generates, teacher customises)',
     'Chan, Kim et al. — Human-AI Collaboration Framework',
     'Three collaboration modes: AI as assistant, augmenter, and explorer'),
    ('CSV and PDF export with customisation support',
     'Del Valle (2025)',
     'Teacher preferences for well-structured, exportable AI output'),
    ('Dual-provider AI failover (DeepSeek to Gemini)',
     'Multiple papers',
     'Service reliability and continuous availability for production deployment'),
    ('Offline-first architecture with SQLite local database',
     'Multiple papers / Nigerian context requirement',
     'Addressing connectivity constraints in developing country educational settings'),
]
for row_data in mapping_data:
    add_table_row(table4, row_data)

doc.add_paragraph()

doc.add_heading('4.3 Discussion of Findings', level=2)

doc.add_heading('4.3.1 Curriculum-Aware Content Generation', level=3)
add_justified_text(
    'The implementation of curriculum-aware prompt templates in ClassAI demonstrates how findings '
    'from the Imagine Learning (2025) white paper can be operationalised in a practical system. '
    'By embedding curriculum metadata — including subject, class level, curriculum type, week number, '
    'topic, difficulty, and Bloom\'s Taxonomy verbs — directly into the LLM prompt, the system guides '
    'the AI to generate content that is explicitly aligned with curriculum specifications. This '
    'approach aligns with Liu et al.\'s (2024) findings that structured prompts significantly '
    'improve the relevance and accuracy of AI-generated educational content.'
)

doc.add_heading('4.3.2 Human-AI Collaboration in Practice', level=3)
add_justified_text(
    'The Human-AI Collaboration Framework proposed by Chan, Kim et al. provides a useful lens for '
    'understanding ClassAI\'s design philosophy. The system operates primarily in the "AI as assistant" '
    'mode — handling the routine, time-intensive task of generating structured, curriculum-aligned '
    'lesson content from teacher-provided parameters. This frees teachers to focus on higher-value '
    'activities such as content customisation, contextualisation, and instructional delivery. '
    'The system also functions in "AI as augmenter" mode by suggesting Bloom\'s Taxonomy-aligned '
    'cognitive levels, vocabulary lists, and assessment strategies.'
)
add_justified_text(
    'The preservice teachers study (2026) warning about over-reliance on AI-generated content '
    'informed the design of ClassAI\'s interactive workflow. The system requires active teacher input '
    'at every stage — from parameter specification to content review and customisation — rather than '
    'offering a one-click "generate and accept" flow. This design choice encourages the critical '
    'engagement with AI-generated content that the study recommends.'
)

doc.add_heading('4.3.3 Structured Content Generation', level=3)
add_justified_text(
    'The structured JSON output schema implemented in ClassAI — with explicit sections for learning '
    'objectives, key vocabulary, materials, lesson presentation, assessment, and homework — addresses '
    'the teacher preference for well-structured AI output identified by Del Valle (2025). The schema '
    'ensures completeness (all essential lesson components are included) and consistency (all generated '
    'lessons follow the same structure, facilitating comparison and quality assurance). This structured '
    'approach also enables the system to validate generated content, identify missing sections, and '
    'provide meaningful feedback to teachers.'
)

doc.add_heading('4.3.4 Security and Privacy Considerations', level=3)
add_justified_text(
    'The security architecture of ClassAI addresses the data protection concerns raised by Mahafdah '
    'et al. (2024). The use of AES-256-GCM encryption ensures that lesson content is protected at rest, '
    'while Argon2id key derivation provides robust protection against brute-force attacks on teacher '
    'passwords. The integration of biometric authentication adds an additional layer of security for '
    'sensitive operations. These measures are particularly important given the sensitive nature of '
    'educational data and the requirements of the Nigeria Data Protection Regulation (NDPR) 2019.'
)

doc.add_heading('4.3.5 Offline-First Architecture for the Nigerian Context', level=3)
add_justified_text(
    'The offline-first architecture of ClassAI addresses a critical requirement for educational '
    'technology deployment in Nigeria — the ability to function without reliable internet connectivity. '
    'The local SQLite database (via Drift ORM) stores all application data, including generated '
    'lesson notes, user accounts, and configuration settings. The credit system allows teachers to '
    'generate content offline using pre-allocated credits that are synchronised when connectivity is '
    'restored. The sync service manages data synchronisation in the background, handling conflicts '
    'through three-way merging and providing visual feedback through the sync indicator widget.'
)

doc.add_page_break()

# ═══════════════════════════════════════════════════════════════
# CHAPTER 5: SUMMARY, RECOMMENDATION AND CONCLUSION
# ═══════════════════════════════════════════════════════════════
doc.add_heading('CHAPTER 5', level=1)
doc.add_heading('SUMMARY, RECOMMENDATION AND CONCLUSION', level=1)

doc.add_heading('5.1 Summary of the Study', level=2)
add_justified_text(
    'This project set out to design and develop ClassAI, an AI-powered, curriculum-aware lesson notes '
    'generator for Nigerian secondary schools. The work was motivated by the identified gap in '
    'standardised, high-quality lesson note preparation facing Nigerian teachers, compounded by '
    'large class sizes, limited resources, insufficient planning time, technological constraints, '
    'and the absence of localised AI-powered educational tools tailored to the NERDC curriculum.'
)
add_justified_text(
    'The project employed a Design Science Research methodology, resulting in the development of a '
    'fully functional cross-platform mobile application built with Flutter and Dart. The system '
    'architecture integrates a local SQLite database (via Drift ORM) for offline operation, a '
    'Supabase cloud backend for synchronisation and authentication, and a dual-provider AI engine '
    '(DeepSeek with Gemini fallback) for content generation. The system supports three curricula '
    '(NERDC, Cambridge, CCSS), 18 core Nigerian secondary school subjects, Bloom\'s Taxonomy-aligned '
    'cognitive level targeting, and a secure offline-first credit system integrated with Paystack '
    'payment processing.'
)
add_justified_text(
    'A comprehensive review of ten recent research papers on AI in education was conducted, covering '
    'curriculum-informed AI, generative AI-powered educational alignment, AI in curriculum development, '
    'AI-assisted lesson generation, human-AI collaboration in education, and personalised learning. '
    'Findings from these papers directly informed the design and feature set of ClassAI, ensuring '
    'that the system is grounded in current research while addressing the practical requirements of '
    'the Nigerian educational context.'
)

doc.add_heading('5.2 Conclusion', level=2)
add_justified_text(
    'This project has demonstrated that AI-powered, curriculum-aware lesson notes generation is both '
    'feasible and implementable for the Nigerian secondary education context. The ClassAI system '
    'successfully addresses the key challenges of lesson note preparation by leveraging large '
    'language models to generate structured, curriculum-aligned content. The system\'s architecture '
    '— incorporating offline-first capabilities, multi-curriculum support, robust security, and '
    'a dual-provider AI failover mechanism — provides a practical template for AI-powered educational '
    'tools deployed in developing country contexts.'
)
add_justified_text(
    'The project makes several important contributions. First, it demonstrates how findings from '
    'contemporary AI education research can be synthesised and implemented in a practical application. '
    'Second, it presents a viable architecture for offline-first AI-powered educational tools in '
    'low-connectivity environments, addressing a critical barrier to educational technology adoption '
    'in developing countries. Third, it provides a practical integration of local payment systems '
    '(Paystack) with AI content generation, enabling a sustainable deployment model.'
)
add_justified_text(
    'The findings affirm that AI in education should be positioned as a teacher-assistance tool '
    'that augments rather than replaces teacher expertise. The most effective deployment model is '
    'one where AI handles the routine aspects of content generation — structure, curriculum alignment, '
    'and baseline quality — while teachers apply their professional judgment in customising, '
    'contextualising, and delivering the content to their specific students.'
)

doc.add_heading('5.3 Contributions to Knowledge', level=2)
add_justified_text('This project makes the following contributions to knowledge:')
add_bullet('Development of a curriculum-aware prompt engineering framework that integrates NERDC curriculum specifications with Bloom\'s Taxonomy cognitive levels for AI-powered lesson note generation.')
add_bullet('Design and implementation of an offline-first AI content generation architecture specifically optimised for low-connectivity environments in developing countries, including a dual-provider AI failover mechanism, local credit management, and conflict-free data synchronisation.')
add_bullet('A systematic synthesis of ten recent AI education research papers, mapping their findings to implementable system features — providing a model for research-driven educational technology development.')
add_bullet('A replicable system architecture for integrating local payment gateways (Paystack) with AI-powered educational tools, including offline credit management and subscription-based access control.')
add_bullet('Comprehensive documentation of the technological, pedagogical, and contextual considerations for deploying AI-powered educational tools in Nigerian secondary schools, providing guidance for developers, educators, and policymakers.')

doc.add_heading('5.4 Recommendations', level=2)
add_justified_text('Based on the findings of this project, the following recommendations are made:')

add_justified_text('5.4.1 Recommendations for Teachers', bold=True, indent_first=False)
add_bullet('Adopt ClassAI as a lesson planning assistant to reduce preparation time while maintaining content quality and curriculum alignment.')
add_bullet('Regularly review and customise AI-generated content to reflect local contexts, student abilities, and available teaching resources.')
add_bullet('Use the Bloom\'s Taxonomy targeting feature to design lessons that address multiple cognitive levels and promote higher-order thinking skills.')

add_justified_text('5.4.2 Recommendations for School Administrators', bold=True, indent_first=False)
add_bullet('Deploy ClassAI across subject departments to standardise lesson note quality and facilitate instructional supervision.')
add_bullet('Provide training sessions for teachers on effective use of AI-assisted lesson planning tools.')
add_bullet('Invest in offline-capable devices (tablets, laptops) for teachers to maximise the benefits of the system\'s offline capabilities.')

add_justified_text('5.4.3 Recommendations for Developers', bold=True, indent_first=False)
add_bullet('Expand the system to support additional Nigerian languages and local content formats.')
add_bullet('Implement fine-tuned language models specifically trained on NERDC curriculum data for improved generation accuracy.')
add_bullet('Develop analytics dashboards for school administrators to monitor content generation patterns and quality metrics.')
add_bullet('Conduct empirical evaluation studies with teachers and students to validate system effectiveness in real classroom settings.')

doc.add_heading('5.5 Limitations of the Study', level=2)
add_justified_text('This project has the following limitations:')
add_bullet('The system is in the development phase and has not yet been empirically evaluated with teachers and students in real classroom settings.')
add_bullet('The AI generation quality is inherently dependent on the capabilities and limitations of the underlying LLM providers (DeepSeek and Gemini), which are subject to change as models are updated or deprecated.')
add_bullet('The NERDC curriculum integration is based on publicly available curriculum documentation and may not capture all nuances of the official curriculum as implemented in individual schools.')
add_bullet('The Paystack payment integration has been implemented for the Nigerian market but may require adaptation for deployment in other African countries with different payment ecosystems.')
add_bullet('The system currently supports 18 NERDC subjects but may need extension to cover additional elective subjects offered at the SSS level.')

doc.add_heading('5.6 Suggestions for Future Research', level=2)
add_justified_text('Future research directions emerging from this project include:')
add_bullet('Empirical Evaluation: Conduct controlled studies with teachers and students to assess the impact of AI-generated lesson notes on teaching efficiency, content quality, and student learning outcomes.')
add_bullet('Fine-Tuned Models: Investigate the development of fine-tuned language models specifically trained on NERDC curriculum documents and Nigerian educational content for improved generation accuracy.')
add_bullet('Multilingual Support: Extend the system to support indigenous Nigerian languages (Hausa, Igbo, Yoruba) for lesson generation in language-intensive subjects.')
add_bullet('Adaptive Personalisation: Research adaptive algorithms that dynamically adjust content difficulty based on student performance data and individual learning needs.')
add_bullet('Cross-Curriculum Analysis: Compare the effectiveness of AI-generated lesson notes across different curricula (NERDC, Cambridge, CCSS) to identify best practices for each.')
add_bullet('Teacher Professional Development: Investigate the potential of AI-powered lesson planning tools as platforms for teacher professional development and pedagogical skill enhancement.')

doc.add_page_break()

# ═══════════════════════════════════════════════════════════════
# REFERENCES
# ═══════════════════════════════════════════════════════════════
doc.add_heading('REFERENCES', level=1)

references = [
    'Chan, J., Kim, S., et al. (2025). Learning design to advance human-AI collaboration in K-12 education. Old Dominion University Digital Commons. https://digitalcommons.odu.edu/stemps_fac_pubs/419/',
    'Del Valle, J. M. (2025). Use of generative AI in writing lesson plans. International Journal of Social Science and Humanities Research, 4(7). https://doi.org/10.58806/ijsshmr.2025.v4i7n02',
    'Imagine Learning. (2025). Curriculum-informed AI [White paper]. https://www.imaginelearning.com/wp-content/uploads/2025/04/1620957897_Curriculum_Informed_AI_White_Paper_DIGITAL.pdf',
    'Liu, S., Mendoza, A., Martin, T., & Miori, V. (2024). Generative AI-powered educational alignment. In Proceedings of the ACM International Conference on Distance Education and Learning (ICDEL 2024). https://dl.acm.org/doi/10.1145/3675812.3675874',
    'Mahafdah, K., Bouallegue, M., & Bouallegue, B. (2024). Enhancing e-learning through AI. PeerJ Computer Science. https://pmc.ncbi.nlm.nih.gov/articles/PMC11784796/',
    'Mishra, P., & Koehler, M. J. (2006). Technological pedagogical content knowledge: A framework for teacher knowledge. Teachers College Record, 108(6), 1017-1054.',
    'Mohamed Sapawi, A., & Nik Yusoff, N. (2025). Artificial intelligence in curriculum development. Journal of Curriculum Studies Research. https://curriculumstudies.org/index.php/CS/article/view/635',
    'National Bureau of Statistics. (2023). Statistical report on primary and secondary education in Nigeria. Federal Government of Nigeria.',
    'NCBI PMC. (2025). Designing and evaluating an AI-integrated curriculum [Co-design and evaluation study]. https://www.ncbi.nlm.nih.gov/pmc/articles/PMC12189063/',
    'Nigeria Data Protection Regulation. (2019). Nigeria Data Protection Regulation 2019. National Information Technology Development Agency.',
    'Peffers, K., Tuunanen, T., Rothenberger, M. A., & Chatterjee, S. (2007). A design science research methodology for information systems research. Journal of Management Information Systems, 24(3), 45-77.',
    'Piaget, J. (1972). The psychology of the child. Basic Books.',
    'Preservice Teachers Study. (2026). Exploring the impact of generative AI on curriculum design and instruction: A study with preservice teachers. ResearchGate. https://www.researchgate.net/publication/399686182_Exploring_the_Impact_of_Generative_AI_on_Curriculum_Design_and_Instruction_A_Study_With_Preservice_Teachers',
    'Teachers Registration Council of Nigeria. (2022). Professional standards for Nigerian teachers. TRCN Publications.',
    'Vygotsky, L. S. (1978). Mind in society: The development of higher psychological processes. Harvard University Press.',
    'Wiley. (2026). AI-assisted lesson generation in medical and professional education: A practical guide. https://onlinelibrary.wiley.com/doi/10.1002/mef2.70018',
    'arxiv. (2025). Assessing the impact of AI-generated personalized lesson plans. https://arxiv.org/pdf/2510.19866',
]

for ref in references:
    p = doc.add_paragraph()
    p.paragraph_format.left_indent = Cm(1.27)
    p.paragraph_format.first_line_indent = Cm(-1.27)
    p.paragraph_format.line_spacing = 1.5
    p.paragraph_format.space_after = Pt(6)
    run = p.add_run(ref)
    run.font.name = 'Times New Roman'
    run.font.size = Pt(12)

doc.add_page_break()

# ═══════════════════════════════════════════════════════════════
# APPENDICES
# ═══════════════════════════════════════════════════════════════
doc.add_heading('APPENDICES', level=1)

doc.add_heading('Appendix A: System Configuration and Requirements', level=2)

table5 = doc.add_table(rows=1, cols=2)
table5.style = 'Table Grid'
table5.alignment = WD_TABLE_ALIGNMENT.CENTER
hdr5 = table5.rows[0]
for i, text in enumerate(['Requirement', 'Specification']):
    cell = hdr5.cells[i]
    cell.text = ''
    p = cell.paragraphs[0]
    run = p.add_run(text)
    run.font.name = 'Times New Roman'
    run.font.size = Pt(11)
    run.bold = True
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    shading = parse_xml(f'<w:shd {nsdecls("w")} w:fill="D9E2F3"/>')
    cell._tc.get_or_add_tcPr().append(shading)

app_config = [
    ('Minimum Android Version', 'API 21 (Android 5.0)'),
    ('Minimum iOS Version', 'iOS 12.0'),
    ('Minimum RAM', '3 GB'),
    ('Minimum Storage', '500 MB free space'),
    ('Internet Requirement', 'Not required for core functions (offline-first)'),
    ('Target Platforms', 'Android, iOS, Web, Linux, macOS, Windows'),
    ('State Management', 'Riverpod 3.3.1'),
    ('Local Database', 'SQLite via Drift ORM 2.31.0'),
    ('Cloud Backend', 'Supabase (PostgreSQL)'),
    ('AI Providers', 'DeepSeek (primary), Gemini (fallback)'),
    ('Encryption', 'AES-256-GCM, Argon2id'),
    ('Payment Gateway', 'Paystack'),
]
for row_data in app_config:
    add_table_row(table5, row_data)

doc.add_paragraph()

doc.add_heading('Appendix B: Database Table Schema Summary', level=2)

table6 = doc.add_table(rows=1, cols=3)
table6.style = 'Table Grid'
table6.alignment = WD_TABLE_ALIGNMENT.CENTER
hdr6 = table6.rows[0]
for i, text in enumerate(['Table Name', 'Purpose', 'Key Fields']):
    cell = hdr6.cells[i]
    cell.text = ''
    p = cell.paragraphs[0]
    run = p.add_run(text)
    run.font.name = 'Times New Roman'
    run.font.size = Pt(10)
    run.bold = True
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    shading = parse_xml(f'<w:shd {nsdecls("w")} w:fill="D9E2F3"/>')
    cell._tc.get_or_add_tcPr().append(shading)

schema_data = [
    ('lessons', 'Generated lesson notes', 'subject, classLevel, week, topic, content (encrypted), curriculum, bloomsVerbs'),
    ('subjects', 'Subject definitions', 'name, code, curriculum, classLevel'),
    ('teachers', 'Teacher profiles', 'email, passwordHash, deviceId, serverId'),
    ('schools', 'School information', 'name, subscriptionTier, expiryDate, address'),
    ('terms', 'Academic terms', 'name, startDate, endDate, schoolLocalId'),
    ('scheme_of_work', 'Topic schedules', 'subject, termId, week, topic, objectives'),
    ('exams', 'Generated exam questions', 'subject, classLevel, type, questions (JSON)'),
    ('sync_queue', 'Sync entries', 'table, operation, rowData, status, retryCount'),
    ('audit_logs', 'Activity audit trail', 'teacherId, schoolId, action, metadata, timestamp'),
    ('security_config', 'Security settings', 'encryptionKey, offlineCredits, dailyGenerations'),
    ('vault_items', 'Encrypted storage', 'itemType, encryptedData, schoolId'),
    ('payment_events', 'Payment records', 'reference, amount, status, subscriptionTier'),
    ('pdf_cache', 'PDF generation cache', 'contentHash, pdfData, createdAt'),
]
for row_data in schema_data:
    add_table_row(table6, row_data)

doc.add_paragraph()

doc.add_heading('Appendix C: Feature-to-Research Mapping Reference', level=2)
add_justified_text(
    'The following table provides a quick-reference mapping of ClassAI features to the ten research '
    'papers reviewed in Chapter 2, showing how each paper informed specific system capabilities.'
)

# Quick ref mapping table
table7 = doc.add_table(rows=1, cols=2)
table7.style = 'Table Grid'
table7.alignment = WD_TABLE_ALIGNMENT.CENTER
hdr7 = table7.rows[0]
for i, text in enumerate(['Research Paper', 'ClassAI Features Informed']):
    cell = hdr7.cells[i]
    cell.text = ''
    p = cell.paragraphs[0]
    run = p.add_run(text)
    run.font.name = 'Times New Roman'
    run.font.size = Pt(10)
    run.bold = True
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    shading = parse_xml(f'<w:shd {nsdecls("w")} w:fill="D9E2F3"/>')
    cell._tc.get_or_add_tcPr().append(shading)

ref_data = [
    ('1. Imagine Learning — Curriculum-Informed AI', 'Prompt template system, curriculum metadata embedding, multi-curriculum support'),
    ('2. Liu et al. — Generative AI-Powered Educational Alignment', 'JSON output schema, content structure, curriculum version tracking'),
    ('3. Mohamed Sapawi & Nik Yusoff — AI in Curriculum Development', 'Academic calendar engine, scheme of work, trimester awareness'),
    ('4. Preservice Teachers Study — GenAI Impact on Curriculum', 'Interactive lesson editor, teacher parameter input, customisation workflow'),
    ('5. Wiley — AI-Assisted Lesson Generation', 'Six-step generation pipeline, structured output, export services'),
    ('6. Mahafdah et al. — Enhancing E-Learning Through AI', 'AES-256-GCM encryption, vault system, access control'),
    ('7. arxiv — AI-Generated Personalised Lesson Plans', 'Audit logging, content validation, quality assurance mechanisms'),
    ('8. NCBI PMC — AI-Integrated Curriculum', 'Teacher parameter control, editable output, merge engine for collaboration'),
    ('9. Chan, Kim et al. — Human-AI Collaboration', 'AI-as-assistant workflow, teacher-as-reviewer design, augmentation features'),
    ('10. Del Valle — GenAI in Writing Lesson Plans', 'Structured format, subject/level parameters, CSV/PDF export'),
]
for row_data in ref_data:
    add_table_row(table7, row_data)

# ───────────────────────────────────────────────────────────────
# SAVE DOCUMENT
# ───────────────────────────────────────────────────────────────
output_path = 'c:/Users/Yene/classai/ClassAI_Masters_Thesis.docx'
doc.save(output_path)
print(f'Document saved successfully to: {output_path}')
