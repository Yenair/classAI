"""
Generate the complete revised ClassAI thesis as a Word document (.docx)
with all modifications specified by the user.
"""

from docx import Document
from docx.shared import Pt, Inches, Cm, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.oxml.ns import qn, nsdecls
from docx.oxml import parse_xml
import os

doc = Document()

# ─── Global style setup ──────────────────────────────────────────────
style = doc.styles['Normal']
font = style.font
font.name = 'Times New Roman'
font.size = Pt(12)
style.paragraph_format.line_spacing = 1.5
style.paragraph_format.space_after = Pt(0)
style.paragraph_format.space_before = Pt(0)

# Helper: set cell borders (gridlines) on a table
def set_table_borders(table):
    """Apply borders to all cells in a table."""
    tbl = table._tbl
    tblPr = tbl.tblPr if tbl.tblPr is not None else parse_xml(f'<w:tblPr {nsdecls("w")}/>')
    borders = parse_xml(
        f'<w:tblBorders {nsdecls("w")}>'
        '  <w:top w:val="single" w:sz="4" w:space="0" w:color="000000"/>'
        '  <w:left w:val="single" w:sz="4" w:space="0" w:color="000000"/>'
        '  <w:bottom w:val="single" w:sz="4" w:space="0" w:color="000000"/>'
        '  <w:right w:val="single" w:sz="4" w:space="0" w:color="000000"/>'
        '  <w:insideH w:val="single" w:sz="4" w:space="0" w:color="000000"/>'
        '  <w:insideV w:val="single" w:sz="4" w:space="0" w:color="000000"/>'
        '</w:tblBorders>'
    )
    tblPr.append(borders)

def add_cell_text(cell, text, bold=False, size=10, align=WD_ALIGN_PARAGRAPH.LEFT):
    """Set cell text with formatting."""
    for p in cell.paragraphs:
        p.clear()
    p = cell.paragraphs[0]
    p.alignment = align
    run = p.add_run(text)
    run.font.name = 'Times New Roman'
    run.font.size = Pt(size)
    run.bold = bold
    p.paragraph_format.space_after = Pt(0)
    p.paragraph_format.space_before = Pt(0)

def add_table_with_data(headers, rows, col_widths=None):
    """Create a table with borders and return it."""
    table = doc.add_table(rows=1 + len(rows), cols=len(headers))
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    set_table_borders(table)
    # Header row
    for i, h in enumerate(headers):
        add_cell_text(table.rows[0].cells[i], h, bold=True, size=10)
    # Data rows
    for ri, row_data in enumerate(rows):
        for ci, cell_text in enumerate(row_data):
            add_cell_text(table.rows[ri + 1].cells[ci], cell_text, size=10)
    # Column widths
    if col_widths:
        for row in table.rows:
            for i, w in enumerate(col_widths):
                row.cells[i].width = Cm(w)
    return table

# ════════════════════════════════════════════════════════════════════
# TITLE PAGE
# ════════════════════════════════════════════════════════════════════
for _ in range(6):
    doc.add_paragraph()

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
run = p.add_run('CLASSAI: AI CURRICULUM-AWARE LESSON NOTES\nGENERATOR FOR NIGERIAN SECONDARY SCHOOLS')
run.bold = True
run.font.size = Pt(16)
run.font.name = 'Times New Roman'

doc.add_paragraph()
p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
run = p.add_run('BY')
run.bold = True
run.font.size = Pt(14)

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
run = p.add_run('Umoh, Yeneabasi Alex\n20/EG/CO/1359')
run.font.size = Pt(14)
run.font.name = 'Times New Roman'

doc.add_paragraph()
doc.add_paragraph()

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
run = p.add_run('A PROJECT REPORT\nPRESENTED TO THE DEPARTMENT OF COMPUTER ENGINEERING\nFACULTY OF ENGINEERING\nUniversity Of Uyo,\nUyo, Akwa Ibom State, Nigeria')
run.font.size = Pt(12)
run.font.name = 'Times New Roman'

doc.add_paragraph()
p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
run = p.add_run('IN PARTIAL FULFILMENT OF THE REQUIREMENTS\nFOR THE AWARD OF THE DEGREE OF\nBACHELOR OF ENGINEERING (B.ENG) IN COMPUTER ENGINEERING')
run.font.size = Pt(12)
run.font.name = 'Times New Roman'

doc.add_paragraph()
p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
run = p.add_run('July, 2026')
run.font.size = Pt(12)
run.font.name = 'Times New Roman'

doc.add_page_break()

# ════════════════════════════════════════════════════════════════════
# TABLE OF CONTENTS
# ════════════════════════════════════════════════════════════════════
p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
run = p.add_run('TABLE OF CONTENTS')
run.bold = True
run.font.size = Pt(14)

toc_entries = [
    ('Title Page', 'i'),
    ('Table of Contents', 'ii'),
    ('Abstract', 'iii'),
    ('CHAPTER 1: INTRODUCTION', '1'),
    ('    1.1 Background to the Study', '1'),
    ('    1.2 Statement of the Problem', '3'),
    ('    1.3 Aim and Objectives of the Study', '4'),
    ('    1.4 Justification of the Study', '5'),
    ('    1.5 Scope and Delimitation', '6'),
    ('    1.6 Limitations of the Study', '6'),
    ('    1.7 Organisation of the Report', '7'),
    ('CHAPTER 2: LITERATURE REVIEW', '8'),
    ('    2.1 Preamble: The Nigerian Educational System and Foundational Technologies', '8'),
    ('    2.2 Review of Related Literature', '12'),
    ('    2.3 Theoretical Framework', '22'),
    ('    2.4 Summary', '24'),
    ('CHAPTER 3: METHODOLOGY', '25'),
    ('    3.1 Research Design', '25'),
    ('    3.2 System Architecture and Design', '25'),
    ('    3.3 Implementation Details', '29'),
    ('    3.4 Technology Stack', '31'),
    ('CHAPTER 4: SYSTEM DEVELOPMENT AND RESULTS', '32'),
    ('    4.1 System Implementation Results', '32'),
    ('    4.2 Feature Mapping to Research Literature', '35'),
    ('    4.3 Discussion of Findings', '37'),
    ('CHAPTER 5: SUMMARY, RECOMMENDATION AND CONCLUSION', '40'),
    ('    5.1 Summary of the Study', '40'),
    ('    5.2 Conclusion', '41'),
    ('    5.3 Contributions to Knowledge', '41'),
    ('    5.4 Recommendations', '42'),
    ('    5.5 Suggestions for Future Research', '43'),
    ('References', '44'),
    ('Appendices', '48'),
]

for entry, page in toc_entries:
    p = doc.add_paragraph()
    run = p.add_run(entry)
    run.font.size = Pt(12)
    run.font.name = 'Times New Roman'
    # Right-align page number with tab
    tab_run = p.add_run(f'\t{page}')
    tab_run.font.size = Pt(12)
    tab_run.font.name = 'Times New Roman'

doc.add_page_break()

# ════════════════════════════════════════════════════════════════════
# ABSTRACT (single paragraph, no keywords)
# ════════════════════════════════════════════════════════════════════
p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
run = p.add_run('ABSTRACT')
run.bold = True
run.font.size = Pt(14)

abstract_text = (
    'The integration of Artificial Intelligence (AI) in educational content generation presents a transformative '
    'opportunity for improving teaching quality in secondary schools. This project focuses on the design and development '
    'of ClassAI, an AI-powered, curriculum-aware lesson notes generator specifically tailored for Nigerian secondary '
    'schools operating under the Nigerian Educational Research and Development Council (NERDC) curriculum framework. '
    'The system addresses the critical challenge of standardised, high-quality lesson note preparation that many '
    'Nigerian teachers face due to large class sizes, limited resources, and insufficient planning time. ClassAI was '
    'developed as a cross-platform mobile application using Flutter and Dart, employing a three-tier architecture '
    'comprising a local SQLite database (via Drift ORM), a Supabase cloud backend, and an AI generation engine that '
    'supports both DeepSeek and Gemini large language models with automatic failover. The system incorporates '
    'offline-first capabilities, secure end-to-end encryption using AES-256-GCM, Argon2id key derivation, and a '
    'conflict-free replicated data synchronisation mechanism designed for intermittent internet connectivity typical '
    'in Nigerian educational settings. The application supports multi-curriculum generation including NERDC (Nigeria), '
    'Cambridge International, and Common Core State Standards (CCSS), with Bloom\'s Taxonomy-aligned cognitive level '
    'targeting. The research methodology employed a design science research approach, combining iterative system '
    'development with a comprehensive review of ten recent research papers on AI in education. The system architecture '
    'and features were designed based on insights from these studies, covering curriculum-informed AI, generative '
    'AI-powered educational alignment, AI in curriculum development, AI-assisted lesson generation, human-AI '
    'collaboration in education, and personalised learning. The project demonstrates how findings from contemporary '
    'AI education research can be synthesised and implemented in a practical, offline-first application tailored to '
    'the Nigerian educational context.'
)
p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
run = p.add_run(abstract_text)
run.font.size = Pt(12)
run.font.name = 'Times New Roman'

doc.add_page_break()

# ════════════════════════════════════════════════════════════════════
# CHAPTER 1: INTRODUCTION
# ════════════════════════════════════════════════════════════════════
p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
run = p.add_run('CHAPTER 1\nINTRODUCTION')
run.bold = True
run.font.size = Pt(14)

# 1.1 Background to the Study
p = doc.add_paragraph()
run = p.add_run('1.1 Background to the Study')
run.bold = True
run.font.size = Pt(12)

paras_1_1 = [
    'Education remains the bedrock of national development, and the quality of instruction delivered in secondary '
    'schools directly impacts the human capital development of any nation. In Nigeria, the secondary education system '
    'is governed by the National Policy on Education (NPE), which stipulates a standardised curriculum developed and '
    'maintained by the Nigerian Educational Research and Development Council (NERDC). This curriculum defines the '
    'learning objectives, content, and assessment standards for all subjects taught across Junior Secondary School '
    '(JSS) and Senior Secondary School (SSS) levels.',
    
    'A critical component of effective teaching is the preparation of comprehensive lesson notes — structured documents '
    'that outline learning objectives, instructional materials, presentation procedures, assessment methods, and '
    'homework assignments for each lesson. According to the Teachers Registration Council of Nigeria (TRCN), proper '
    'lesson note preparation is a mandatory professional requirement for all practicing teachers. However, many '
    'Nigerian teachers struggle with this task due to several compounding factors.',
    
    'First, the average teacher-to-student ratio in Nigerian public secondary schools ranges from 1:40 to 1:100 '
    'depending on the region [1], leaving teachers with limited time for individual lesson planning. Second, access '
    'to teaching resources and reference materials remains inadequate, particularly in rural schools. Third, the '
    'administrative burden on teachers extends beyond lesson preparation to include grading, record-keeping, and '
    'extracurricular responsibilities. These challenges collectively compromise the quality and consistency of lesson '
    'notes prepared by teachers.',
    
    'Recent advances in Artificial Intelligence (AI), particularly in the domain of Large Language Models (LLMs), '
    'have opened new possibilities for automating educational content generation. Models such as DeepSeek and '
    'Google\'s Gemini have demonstrated remarkable capabilities in generating coherent, contextually relevant, and '
    'pedagogically sound educational content. These technologies can be harnessed to create AI-powered tools that '
    'assist teachers in generating curriculum-aligned lesson notes efficiently and consistently.',
    
    'Despite the proliferation of AI educational tools globally, there remains a significant gap in solutions '
    'specifically designed for the Nigerian educational context. Most existing platforms cater to Western curricula '
    '(e.g., Common Core, Cambridge International) and lack awareness of the NERDC curriculum structure, Nigerian '
    'cultural context, and the unique technological constraints — such as unreliable internet connectivity and '
    'limited access to modern devices — prevalent in many Nigerian schools. This project addresses this gap by '
    'designing and developing ClassAI, an AI-powered lesson notes generator that is curriculum-aware, offline-first, '
    'and specifically optimised for Nigerian secondary schools.',
]

for text in paras_1_1:
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
    run = p.add_run(text)
    run.font.size = Pt(12)
    run.font.name = 'Times New Roman'

# 1.2 Statement of the Problem
p = doc.add_paragraph()
run = p.add_run('1.2 Statement of the Problem')
run.bold = True
run.font.size = Pt(12)

problem_items = [
    'The preparation of standardised, high-quality lesson notes remains a persistent challenge in Nigerian secondary '
    'education. Teachers are expected to produce detailed lesson plans that align with NERDC curriculum specifications, '
    'incorporate appropriate pedagogical strategies, and address diverse learning needs. However, the following problems '
    'have been identified:',
    'Inadequate lesson planning time: Teachers manage heavy workloads with limited planning periods, resulting in '
    'rushed or incomplete lesson notes.',
    'Inconsistent content quality: The absence of standardised templates and quality assurance mechanisms leads to '
    'wide variation in lesson note quality across schools and teachers.',
    'Limited curriculum awareness: Many teachers, particularly those newly deployed or teaching multiple subjects, '
    'lack deep familiarity with curriculum specifications and expected learning outcomes.',
    'Technological constraints: Existing educational technology platforms require constant internet connectivity, '
    'which is unreliable and expensive in many parts of Nigeria.',
    'Absence of localised solutions: Most AI-powered educational tools are designed for Western educational systems '
    'and do not account for the NERDC curriculum structure, Nigerian cultural nuances, or locally relevant teaching '
    'resources.',
    'These problems collectively undermine the quality of instructional delivery and, consequently, student learning '
    'outcomes. There is a pressing need for an intelligent, context-aware, and offline-capable system that can assist '
    'Nigerian teachers in generating curriculum-aligned lesson notes efficiently and consistently.',
]

for i, text in enumerate(problem_items):
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
    run = p.add_run(text)
    run.font.size = Pt(12)
    run.font.name = 'Times New Roman'
    if i == 0:
        pass
    elif i < 6:
        # Use bullet style for list items
        p.paragraph_format.left_indent = Cm(1.27)
        p.paragraph_format.first_line_indent = Cm(-0.63)

# 1.3 Aim and Objectives of the Study
p = doc.add_paragraph()
run = p.add_run('1.3 Aim and Objectives of the Study')
run.bold = True
run.font.size = Pt(12)

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
run = p.add_run(
    'The aim of this project is to design and develop an AI-powered, curriculum-aware lesson notes generator '
    '(ClassAI) for Nigerian secondary schools. The specific objectives are to:'
)
run.font.size = Pt(12)
run.font.name = 'Times New Roman'

objectives = [
    'Design a system architecture that integrates AI language models with NERDC curriculum specifications for '
    'automated lesson note generation.',
    'Develop a cross-platform mobile application using Flutter framework that implements offline-first capabilities, '
    'secure data storage with AES-256-GCM encryption, and resilient synchronisation mechanisms.',
    'Implement a dual-AI provider system with DeepSeek as the primary and Gemini as the fallback language model, '
    'ensuring continuous availability of content generation services.',
    'Build an academic calendar engine that provides term-aware week numbering aligned with the NERDC trimester '
    'schedule (First Term: September-December, Second Term: January-April, Third Term: May-July).',
    'Integrate a Paystack-based subscription payment system to support sustainable deployment across Nigerian schools.',
    'Align system features with findings from contemporary research on AI in education, including curriculum-informed '
    'AI, generative AI-powered educational alignment, and human-AI collaboration frameworks.',
]

for obj in objectives:
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
    p.paragraph_format.left_indent = Cm(1.27)
    p.paragraph_format.first_line_indent = Cm(-0.63)
    run = p.add_run(obj)
    run.font.size = Pt(12)
    run.font.name = 'Times New Roman'

# 1.4 Justification of the Study (formerly Significance of the Study)
p = doc.add_paragraph()
run = p.add_run('1.4 Justification of the Study')
run.bold = True
run.font.size = Pt(12)

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
run = p.add_run(
    'This project holds significant implications for various stakeholders in the Nigerian education sector:'
)
run.font.size = Pt(12)
run.font.name = 'Times New Roman'

justifications = [
    'Teachers: The system provides a practical tool that reduces lesson planning time while maintaining content '
    'quality, enabling teachers to focus more on instructional delivery and student engagement.',
    'Students: Improved lesson note quality directly translates to better learning experiences and outcomes, as '
    'lessons are more structured, comprehensive, and aligned with curriculum objectives.',
    'School Administrators: Standardised lesson note generation facilitates quality assurance and supervision, '
    'allowing school leaders to monitor instructional quality more effectively.',
    'Researchers: The project contributes a practical implementation that synthesises findings from multiple AI '
    'education research papers into a working system.',
    'Policymakers: The system demonstrates how AI technologies can be leveraged for educational content generation '
    'in developing country contexts, informing future policy decisions.',
]

for j in justifications:
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
    p.paragraph_format.left_indent = Cm(1.27)
    p.paragraph_format.first_line_indent = Cm(-0.63)
    run = p.add_run(j)
    run.font.size = Pt(12)
    run.font.name = 'Times New Roman'

# 1.5 Scope and Delimitation
p = doc.add_paragraph()
run = p.add_run('1.5 Scope and Delimitation')
run.bold = True
run.font.size = Pt(12)

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
run = p.add_run(
    'This project focuses on the design and development of ClassAI as an AI-powered lesson notes generator. The '
    'scope covers: (1) integration with the NERDC curriculum for Nigerian secondary schools (JSS 1-3 and SSS 1-3), '
    '(2) support for 18 core subjects including English Studies, Mathematics, Basic Science, Social Studies, and '
    'Nigerian languages, (3) cross-platform deployment on Android, iOS, Web, and desktop platforms using Flutter, '
    '(4) offline-first operation with synchronisation capabilities, (5) AI-based generation using DeepSeek and Gemini '
    'language models with automatic failover, and (6) alignment of system features with findings from ten recent '
    'research papers on AI in education.\n\n'
    'The project does not cover primary or tertiary education institutions. The AI generation capabilities are '
    'constrained to the capabilities and limitations of the underlying LLM providers. The system\'s payment '
    'integration is limited to Paystack as the payment gateway. Empirical evaluation with teachers and students '
    'is outside the current scope, as the project is in the development phase.'
)
run.font.size = Pt(12)
run.font.name = 'Times New Roman'

# 1.6 Limitations of the Study (moved from old 5.5)
p = doc.add_paragraph()
run = p.add_run('1.6 Limitations of the Study')
run.bold = True
run.font.size = Pt(12)

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
run = p.add_run(
    'The present study is subject to the following limitations:'
)
run.font.size = Pt(12)
run.font.name = 'Times New Roman'

limitations = [
    'The system is in the development phase and has not yet been empirically evaluated with teachers and students '
    'in real classroom settings.',
    'The AI generation quality is inherently dependent on the capabilities and limitations of the underlying LLM '
    'providers (DeepSeek and Gemini), which are subject to change as models are updated or deprecated.',
    'The NERDC curriculum integration is based on publicly available curriculum documentation and may not capture '
    'all nuances of the official curriculum as implemented in individual schools.',
    'The Paystack payment integration has been implemented for the Nigerian market but may require adaptation for '
    'deployment in other African countries with different payment ecosystems.',
    'The system currently supports 18 NERDC subjects but may need extension to cover additional elective subjects '
    'offered at the SSS level.',
]

for l in limitations:
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
    p.paragraph_format.left_indent = Cm(1.27)
    p.paragraph_format.first_line_indent = Cm(-0.63)
    run = p.add_run(l)
    run.font.size = Pt(12)
    run.font.name = 'Times New Roman'

# 1.7 Organisation of the Report
p = doc.add_paragraph()
run = p.add_run('1.7 Organisation of the Report')
run.bold = True
run.font.size = Pt(12)

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
run = p.add_run(
    'This report is organised into five chapters. Chapter 1 provides the introduction, background, problem statement, '
    'objectives, justification, scope, limitations, and organisation of the project. Chapter 2 begins with a preamble '
    'on the Nigerian educational system and foundational technologies, followed by a comprehensive review of ten '
    'recent research papers on AI in education, the theoretical framework, and a summary. Chapter 3 describes the '
    'methodology, including the system architecture design, implementation approach, and technology stack. Chapter 4 '
    'presents the system implementation results and discusses how the features map to the research literature. '
    'Chapter 5 concludes the report with a summary, conclusion, contributions to knowledge, recommendations, and '
    'suggestions for future work.'
)
run.font.size = Pt(12)
run.font.name = 'Times New Roman'

doc.add_page_break()

# ════════════════════════════════════════════════════════════════════
# CHAPTER 2: LITERATURE REVIEW
# ════════════════════════════════════════════════════════════════════
p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
run = p.add_run('CHAPTER 2\nLITERATURE REVIEW')
run.bold = True
run.font.size = Pt(14)

# 2.1 Preamble: The Nigerian Educational System and Foundational Technologies
p = doc.add_paragraph()
run = p.add_run('2.1 Preamble: The Nigerian Educational System and Foundational Technologies')
run.bold = True
run.font.size = Pt(12)

preamble_paras = [
    # Nigerian Education System
    'The Nigerian education system is structured into three tiers: primary education (six years), junior secondary '
    'education (three years, JSS 1-3), and senior secondary education (three years, SSS 1-3). This 6-3-3 structure '
    'is mandated by the National Policy on Education (NPE), and the curriculum for all levels is developed and '
    'maintained by the Nigerian Educational Research and Development Council (NERDC). The NERDC curriculum specifies '
    'learning objectives, content scope, and assessment standards for each subject at each grade level. Nigerian '
    'secondary schools operate on a trimester academic calendar: First Term (September-December), Second Term '
    '(January-April), and Third Term (May-July), with holidays between terms. The concept of a national curriculum '
    'ensures standardisation across all schools, but also creates a need for teachers to prepare lesson notes that '
    'are aligned with the centrally defined curriculum while addressing the diverse contexts of their individual '
    'classrooms [17].',

    # LLMs
    'A Large Language Model (LLM) is a type of artificial intelligence model trained on vast amounts of text data '
    'to understand and generate human-like text. LLMs such as OpenAI\'s GPT series, Google\'s Gemini, and DeepSeek '
    'have demonstrated remarkable capabilities in tasks including text generation, summarisation, translation, and '
    'question answering. For educational content generation, LLMs can be prompted to produce structured lesson notes '
    'aligned with specific curriculum requirements, learning objectives, and pedagogical approaches. The key advantage '
    'of LLMs for lesson note creation is their ability to generate coherent, contextually relevant, and pedagogically '
    'structured content from minimal input parameters provided by the teacher.',

    # Flutter and Dart
    'Flutter is an open-source UI software development toolkit created by Google that enables the development of '
    'cross-platform applications from a single codebase. Using the Dart programming language, Flutter compiles to '
    'native machine code for Android, iOS, Web, Linux, macOS, and Windows platforms. For the ClassAI project, '
    'Flutter\'s cross-platform capabilities allow the same application to run on teachers\' Android tablets, iOS '
    'smartphones, and desktop computers, maximising accessibility across diverse device ecosystems common in Nigerian '
    'schools. Flutter\'s offline capabilities, local storage support via SQLite, and reactive UI framework make it '
    'particularly suitable for educational tools that must function reliably in low-connectivity environments. The '
    'Dart language provides strong typing, asynchronous programming support, and a rich package ecosystem that '
    'facilitates the implementation of complex application logic including cryptography, state management, and '
    'network communication.',

    # Supabase
    'Supabase is an open-source Firebase alternative that provides a suite of backend services including a '
    'PostgreSQL database, authentication, real-time subscriptions, and storage APIs. For ClassAI, Supabase serves '
    'as the cloud backend, handling user authentication, synchronising data between devices, and providing real-time '
    'updates for collaborative workflows. The PostgreSQL database with Row-Level Security (RLS) policies ensures '
    'that data access is properly scoped to authorised users. Supabase\'s real-time capabilities enable immediate '
    'synchronisation when connectivity is available, while its offline-compatible client libraries support the '
    'offline-first architecture that is critical for deployment in Nigerian schools.',

    # Drift
    'Drift (formerly known as Moor) is a reactive ORM (Object-Relational Mapper) for Dart that provides type-safe '
    'access to SQLite databases. For ClassAI, Drift manages the local database containing lesson notes, scheme of '
    'work data, user profiles, and synchronisation state. Drift\'s reactive query capabilities allow the UI to '
    'automatically update when underlying data changes, which is essential for the responsive user experience needed '
    'in an educational application. The ORM\'s migration support ensures that database schema changes can be applied '
    'safely across application updates.',

    # Riverpod
    'Riverpod is a state management library for Dart and Flutter that improves upon the Provider pattern by offering '
    'compile-time safety, better testability, and support for complex dependency graphs. In ClassAI, Riverpod '
    'manages application state across the entire widget tree, including authentication state, credit balances, '
    'synchronisation status, and UI state for the lesson editor. The library\'s ability to handle asynchronous '
    'operations and dispose resources automatically makes it well-suited for managing the complex, async-heavy '
    'workflows in the application.',

    # Paystack
    'Paystack is a Nigerian payment processing platform that enables businesses to accept payments via credit/debit '
    'cards, bank transfers, and mobile money. For ClassAI, Paystack handles subscription payments for the various '
    'tiered plans (Basic, Standard, Elite). Paystack\'s API supports transaction initialisation, verification via '
    'webhooks, and recurring billing. Integration with Paystack allows the application to operate within the '
    'Nigerian financial ecosystem, accepting payments in Nigerian Naira (NGN) without requiring international '
    'payment infrastructure.',

    # AES-256-GCM Encryption
    'AES-256-GCM (Advanced Encryption Standard with 256-bit keys in Galois/Counter Mode) is a symmetric encryption '
    'algorithm that provides both confidentiality and authenticity of data. In ClassAI, AES-256-GCM is used to '
    'encrypt lesson note content at rest in the local SQLite database. The encryption key is derived from the '
    'teacher\'s password using the Argon2id key derivation function, which provides resistance against brute-force '
    'attacks. This security architecture ensures that even if a device is compromised, the lesson content remains '
    'protected. The combination of AES-256-GCM encryption with Argon2id key derivation aligns with the data '
    'protection requirements specified in the Nigeria Data Protection Regulation (NDPR) 2019 [16].',
]

for text in preamble_paras:
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
    run = p.add_run(text)
    run.font.size = Pt(12)
    run.font.name = 'Times New Roman'

# 2.2 Review of Related Literature
p = doc.add_paragraph()
run = p.add_run('2.2 Review of Related Literature')
run.bold = True
run.font.size = Pt(12)

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
run = p.add_run(
    'This section presents a comprehensive review of ten recent research papers on the application of Artificial '
    'Intelligence in education. Each paper is reviewed in terms of its key findings, methodology, and relevance to '
    'the design and development of ClassAI. The review is structured to highlight how findings from each study '
    'informed specific features and architectural decisions in the ClassAI system.'
)
run.font.size = Pt(12)
run.font.name = 'Times New Roman'

# 2.2.1
p = doc.add_paragraph()
run = p.add_run('2.2.1 Curriculum-Informed AI [2]')
run.bold = True
run.font.size = Pt(12)

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
run = p.add_run(
    'The Imagine Learning white paper on Curriculum-Informed AI [2] presents a comprehensive framework for '
    'integrating curriculum standards directly into AI model training and prompt engineering. The paper argues that '
    'for AI to be effective in educational settings, it must be "curriculum-informed" — meaning the AI system must '
    'have explicit awareness of curriculum standards, learning progressions, and grade-level expectations. The '
    'authors demonstrate that curriculum-informed AI significantly outperforms generic AI in generating content that '
    'is pedagogically appropriate and standards-aligned.\n\n'
    'Relevance to ClassAI: This paper directly influenced the design of ClassAI\'s prompt template system. The '
    'PromptTemplates class in ClassAI constructs detailed prompts that embed curriculum metadata — including subject, '
    'curriculum type (NERDC, Cambridge, CCSS), class level, week number, topic, difficulty level, and Bloom\'s '
    'Taxonomy verbs. This ensures that the AI generation is explicitly guided by curriculum specifications. The '
    'system also implements the curriculum type enumeration (CurriculumType enum in curriculum_types.dart) that '
    'supports three curricula with version tracking, mirroring the curriculum-informed approach advocated by '
    'Imagine Learning.'
)
run.font.size = Pt(12)
run.font.name = 'Times New Roman'

# 2.2.2
p = doc.add_paragraph()
run = p.add_run('2.2.2 Generative AI-Powered Educational Alignment [3]')
run.bold = True
run.font.size = Pt(12)

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
run = p.add_run(
    'Liu, Mendoza, Martin, and Miori [3] presented their work at ACM ICDEL 2024 on generative AI-powered educational '
    'alignment. Their research investigates how generative AI models can be used to automatically align educational '
    'content with predefined learning standards and objectives. The study proposes a framework that uses LLMs to map '
    'content to standard learning outcomes, identify gaps in coverage, and suggest remediation. The authors '
    'demonstrated that their approach achieved 85% alignment accuracy when tested against human expert evaluations.\n\n'
    'Relevance to ClassAI: This paper informed the design of ClassAI\'s content structure for lesson notes. The '
    'system\'s JSON output schema — which includes structured fields for learning objectives, key vocabulary, '
    'materials, lesson presentation, assessment, and homework — was designed to ensure that generated content covers '
    'all essential pedagogical components. The alignment verification logic in the merge engine (MergeEngine class) '
    'provides field-level conflict detection that can be extended to verify curriculum alignment. The curriculum '
    'type enumeration with version tracking (nerdc_v2024, cambridge_v2025, ccss_v2024) supports the version-aware '
    'alignment discussed in this paper.'
)
run.font.size = Pt(12)
run.font.name = 'Times New Roman'

# 2.2.3
p = doc.add_paragraph()
run = p.add_run('2.2.3 Artificial Intelligence in Curriculum Development [4]')
run.bold = True
run.font.size = Pt(12)

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
run = p.add_run(
    'Mohamed Sapawi and Nik Yusoff [4] published a study in the Journal of Curriculum Studies Research examining '
    'the role of artificial intelligence in curriculum development processes. Their research explores how AI can '
    'assist in curriculum mapping, content sequencing, and the identification of prerequisite knowledge structures. '
    'The authors argue that AI can enhance curriculum development by analysing large volumes of curriculum data to '
    'identify patterns, gaps, and optimal learning progressions. They also discuss the importance of human oversight '
    'in AI-assisted curriculum development, emphasising that AI should augment rather than replace human curriculum '
    'expertise.\n\n'
    'Relevance to ClassAI: This paper informed the system\'s approach to academic calendar management and scheme of '
    'work generation. The AcademicCalendarService implements NERDC trimester-aware week numbering, providing the '
    'curriculum context needed for topic scheduling. The scheme_of_work database table stores topic sequences per '
    'term, enabling the system to understand curriculum progression. The emphasis on human oversight is reflected '
    'in ClassAI\'s design philosophy — the system generates draft content that teachers review, customise, and '
    'approve, preserving teacher professional judgment.'
)
run.font.size = Pt(12)
run.font.name = 'Times New Roman'

# 2.2.4
p = doc.add_paragraph()
run = p.add_run('2.2.4 Exploring the Impact of Generative AI on Curriculum Design and Instruction [5]')
run.bold = True
run.font.size = Pt(12)

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
run = p.add_run(
    'A study published on ResearchGate [5] explored the impact of generative AI on curriculum design and instruction '
    'through a study with preservice teachers. The research investigated how teacher-trainees interact with generative '
    'AI tools for lesson planning and how these tools influence their understanding of curriculum design principles. '
    'The findings revealed that preservice teachers who used AI-assisted planning tools demonstrated improved '
    'understanding of curriculum alignment, but also showed tendencies to over-rely on AI-generated content without '
    'critical evaluation. The study recommends that AI tools in education should be designed to encourage active '
    'teacher engagement rather than passive acceptance of generated content.\n\n'
    'Relevance to ClassAI: This paper influenced the interactive design of ClassAI\'s lesson editor screen. The '
    'system requires teachers to actively input parameters such as subject, topic, difficulty level, and Bloom\'s '
    'Taxonomy verbs before generation. The generated content is presented in an editable format, allowing teachers '
    'to modify, add, or remove sections. The lesson_editor_screen.dart and lessons_list_screen.dart implement this '
    'interactive workflow, encouraging the active teacher engagement recommended by this study.'
)
run.font.size = Pt(12)
run.font.name = 'Times New Roman'

# 2.2.5
p = doc.add_paragraph()
run = p.add_run('2.2.5 AI-Assisted Lesson Generation in Professional Education [6]')
run.bold = True
run.font.size = Pt(12)

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
run = p.add_run(
    'A practical guide published by Wiley [6] on AI-assisted lesson generation in medical and professional education '
    'provides structured methodologies for incorporating AI into lesson design workflows. The guide outlines a '
    'step-by-step process: (1) define learning objectives, (2) specify content parameters, (3) generate initial '
    'content with AI, (4) review and refine, (5) add assessment components, and (6) finalise for delivery. The guide '
    'emphasises the importance of structured prompts, clear output specifications, and iterative refinement cycles '
    'for achieving high-quality AI-generated educational content.\n\n'
    'Relevance to ClassAI: This guide\'s six-step workflow maps directly to ClassAI\'s lesson generation pipeline. '
    'The system implements this through: (1) the PromptTemplates class defining structured prompts with explicit '
    'learning objective requirements, (2) the subject, class level, week, and topic input fields on the lesson '
    'editor, (3) the AiService.generate() method with injection detection and token management, (4) the editable '
    'output interface where teachers review generated content, (5) the assessment section automatically included in '
    'the structured JSON output, and (6) the PDF and CSV export services for final content delivery. The '
    'dual-provider failover mechanism (DeepSeek to Gemini) ensures reliability in the generation step.'
)
run.font.size = Pt(12)
run.font.name = 'Times New Roman'

# 2.2.6
p = doc.add_paragraph()
run = p.add_run('2.2.6 Enhancing E-Learning Through AI [7]')
run.bold = True
run.font.size = Pt(12)

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
run = p.add_run(
    'Mahafdah, Bouallegue, and Bouallegue [7] published a study in PeerJ Computer Science examining the enhancement '
    'of e-learning through artificial intelligence. Their research explored various AI techniques — including natural '
    'language processing, machine learning, and recommendation systems — for improving online learning experiences. '
    'The study identified key success factors for AI in e-learning: personalisation of content, adaptive assessment, '
    'real-time feedback, and intelligent content recommendation. The authors also highlighted the importance of data '
    'security and privacy in AI-powered educational systems.\n\n'
    'Relevance to ClassAI: This paper informed several security and content management features. The AES-256-GCM '
    'encryption implementation (encryption_utils.dart) addresses the data security concerns raised in the study. '
    'The vault system (vault_browser_screen.dart, vault_item_detail_screen.dart, vault_publisher_screen.dart) '
    'provides secure storage and controlled publishing of educational content. The credit system (credit_service.dart) '
    'implements intelligent access control, ensuring that content generation resources are allocated appropriately '
    'based on subscription tier.'
)
run.font.size = Pt(12)
run.font.name = 'Times New Roman'

# 2.2.7
p = doc.add_paragraph()
run = p.add_run('2.2.7 Assessing the Impact of AI-Generated Personalised Lesson Plans [8]')
run.bold = True
run.font.size = Pt(12)

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
run = p.add_run(
    'An arxiv paper [8] on assessing the impact of AI-generated personalised lesson plans presented a framework for '
    'evaluating AI-generated educational content. The study proposed evaluation criteria including content accuracy, '
    'pedagogical appropriateness, curriculum alignment, language quality, and completeness. The authors developed a '
    'rubric-based assessment methodology that combines automated evaluation metrics with human expert review. Their '
    'findings indicated that AI-generated lesson plans, when properly prompted, achieved comparable quality ratings '
    'to human-created plans in terms of structure and curriculum alignment, though they sometimes lacked contextual '
    'nuance.\n\n'
    'Relevance to ClassAI: The evaluation framework from this paper influenced the design of ClassAI\'s content '
    'quality assurance mechanisms. The audit_logs database table stores generation metadata including teacher ID, '
    'school ID, topic, and timestamp, enabling quality tracking. The content validation logic in AiService, including '
    'markdown stripping and JSON parsing (_stripMarkdownWrappers method), ensures that generated content conforms '
    'to the expected structured format. The sanitisation utilities (sanitization_utils.dart) implement injection '
    'detection, contributing to content safety and quality.'
)
run.font.size = Pt(12)
run.font.name = 'Times New Roman'

# 2.2.8
p = doc.add_paragraph()
run = p.add_run('2.2.8 Designing and Evaluating an AI-Integrated Curriculum [9]')
run.bold = True
run.font.size = Pt(12)

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
run = p.add_run(
    'A 2025 study published via NCBI PMC [9] examined the co-design and evaluation of AI-integrated curriculum '
    'assessment systems. The research focused on how AI can be integrated into existing curriculum frameworks '
    'through a participatory design approach involving teachers, curriculum developers, and AI specialists. The '
    'study found that successful AI integration requires: (1) alignment with existing curriculum structures, '
    '(2) teacher involvement in the design process, (3) transparent AI decision-making, and (4) robust feedback '
    'mechanisms for continuous improvement.\n\n'
    'Relevance to ClassAI: This paper\'s participatory design principles are reflected in ClassAI\'s architecture. '
    'The system provides teachers with full control over generation parameters, allowing them to specify subject, '
    'class level, week, topic, difficulty, and Bloom\'s Taxonomy levels. The editable lesson output ensures teacher '
    'agency in the final content. The audit logging system provides transparency by recording all generation events. '
    'The merge engine (merge_engine.dart and merge_strategies.dart) with field-level conflict resolution supports '
    'collaborative content workflows where multiple teachers can contribute to content refinement.'
)
run.font.size = Pt(12)
run.font.name = 'Times New Roman'

# 2.2.9
p = doc.add_paragraph()
run = p.add_run('2.2.9 Learning Design to Advance Human-AI Collaboration in K-12 Education [10]')
run.bold = True
run.font.size = Pt(12)

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
run = p.add_run(
    'Chan, Kim, and colleagues [10] published a study through Old Dominion University\'s Digital Commons examining '
    'learning design frameworks for advancing human-AI collaboration in K-12 education. The research proposes a '
    '"Human-AI Collaboration Framework" that identifies three collaboration modes: (1) AI as assistant — handling '
    'routine tasks while humans focus on complex decisions, (2) AI as augmenter — enhancing human capabilities with '
    'AI-generated insights, and (3) AI as explorer — discovering new patterns and possibilities that humans may not '
    'have considered. The study emphasises that educational AI should be designed to complement rather than replace '
    'teacher expertise.\n\n'
    'Relevance to ClassAI: This framework directly shaped ClassAI\'s design philosophy. ClassAI operates primarily '
    'in the "AI as assistant" mode — handling the routine task of generating structured, curriculum-aligned lesson '
    'content from teacher-provided parameters. It also functions in "AI as augmenter" mode by suggesting Bloom\'s '
    'Taxonomy-aligned cognitive levels, vocabulary lists, and assessment strategies that teachers may not have '
    'considered. The system is explicitly designed as a teacher assistance tool, with the teacher remaining the '
    'final decision-maker on content appropriateness. The human-AI collaboration is embedded in the workflow: '
    'teachers specify parameters, AI generates content, and teachers review, customise, and approve the output.'
)
run.font.size = Pt(12)
run.font.name = 'Times New Roman'

# 2.2.10
p = doc.add_paragraph()
run = p.add_run('2.2.10 Use of Generative AI in Writing Lesson Plans [11]')
run.bold = True
run.font.size = Pt(12)

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
run = p.add_run(
    'Del Valle [11] published a study in the International Journal of Social Science and Humanities Research '
    '(IJSSHMR) on the use of generative AI in writing lesson plans. The research surveyed teachers\' experiences '
    'with generative AI tools for lesson planning, examining benefits, challenges, and best practices. Key findings '
    'included: (1) teachers reported significant time savings (averaging 30-45 minutes per lesson plan), (2) '
    'AI-generated content was perceived as well-structured but requiring contextual customisation, (3) teachers '
    'valued the ability to specify grade level and subject parameters, and (4) the most successful implementations '
    'were those where AI handled structure and baseline content while teachers focused on customisation and '
    'contextualisation.\n\n'
    'Relevance to ClassAI: Del Valle\'s findings validate several design decisions in ClassAI. The system\'s '
    'structured lesson note format — with clearly delineated sections for objectives, vocabulary, materials, '
    'presentation, assessment, and homework — addresses the teacher preference for well-structured AI output. The '
    'parameter specification interface (subject, class level, week, topic, difficulty) implements the '
    'teacher-input-driven approach recommended in the study. The export functionality (export_service.dart) '
    'supporting both CSV and PDF formats facilitates the customisation workflow, allowing teachers to export, '
    'modify, and finalise content in their preferred format.'
)
run.font.size = Pt(12)
run.font.name = 'Times New Roman'

# 2.3 Theoretical Framework
p = doc.add_paragraph()
run = p.add_run('2.3 Theoretical Framework')
run.bold = True
run.font.size = Pt(12)

p = doc.add_paragraph()
run = p.add_run('2.3.1 Constructivist Learning Theory')
run.bold = True
run.font.size = Pt(12)

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
run = p.add_run(
    'Constructivist learning theory, rooted in the works of Piaget [12] and Vygotsky [13], posits that learners '
    'actively construct knowledge through interaction with their environment and social context. This theory '
    'emphasises the importance of meaningful, contextually relevant learning experiences that build upon existing '
    'knowledge structures. In the context of lesson note generation, constructivism suggests that effective lesson '
    'plans should incorporate activities that promote active learning, critical thinking, and knowledge construction '
    'rather than passive information transmission.\n\n'
    'ClassAI\'s lesson note generation is grounded in constructivist principles. The generated lesson notes include '
    'structured presentation sections that guide teachers through activity-based learning sequences, incorporating '
    'starter activities, main activities, and plenary sessions. The assessment components are designed to evaluate '
    'higher-order thinking skills aligned with constructivist pedagogy, moving beyond simple recall to application, '
    'analysis, and evaluation tasks.'
)
run.font.size = Pt(12)
run.font.name = 'Times New Roman'

p = doc.add_paragraph()
run = p.add_run('2.3.2 Technological Pedagogical Content Knowledge (TPACK)')
run.bold = True
run.font.size = Pt(12)

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
run = p.add_run(
    'The Technological Pedagogical Content Knowledge (TPACK) framework, developed by Mishra and Koehler [14], '
    'describes the types of knowledge teachers need to effectively integrate technology into their teaching practice. '
    'TPACK identifies three primary knowledge domains — Content Knowledge (CK), Pedagogical Knowledge (PK), and '
    'Technological Knowledge (TK) — and their intersections.\n\n'
    'ClassAI embodies the TPACK framework by providing an AI-powered tool that bridges the gap between content '
    'knowledge (curriculum specifications and subject matter), pedagogical knowledge (teaching strategies, assessment '
    'design, and cognitive level targeting), and technological knowledge (cross-platform mobile application, AI '
    'generation, offline capabilities). The system reduces the technological burden on teachers by automating complex '
    'tasks while preserving their professional autonomy in customising and delivering the generated content.'
)
run.font.size = Pt(12)
run.font.name = 'Times New Roman'

# 2.4 Summary
p = doc.add_paragraph()
run = p.add_run('2.4 Summary')
run.bold = True
run.font.size = Pt(12)

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
run = p.add_run(
    'The ten research papers reviewed in this chapter provide a comprehensive foundation for the design and '
    'development of ClassAI. The literature reveals several key themes that have directly influenced the system '
    'architecture:\n\n'
    'Curriculum Awareness: Multiple studies [2]–[4] emphasise the importance of AI systems being explicitly aware '
    'of curriculum standards. ClassAI addresses this through its prompt template system that embeds curriculum '
    'metadata and its multi-curriculum support (NERDC, Cambridge, CCSS).\n\n'
    'Human-AI Collaboration: The Human-AI Collaboration Framework [10] and the preservice teachers study [5] both '
    'stress that AI should augment rather than replace teacher expertise. ClassAI implements this through its '
    'interactive generation workflow where teachers specify parameters, review output, and customise content.\n\n'
    'Structured Content Generation: The Wiley practical guide [6] and Del Valle [11] demonstrate the importance of '
    'structured, well-formatted AI output. ClassAI\'s JSON schema with explicit sections for objectives, vocabulary, '
    'materials, presentation, assessment, and homework addresses this requirement.\n\n'
    'Security and Privacy: Mahafdah et al. [7] highlight data security concerns in AI-powered educational systems. '
    'ClassAI implements AES-256-GCM encryption, Argon2id key derivation, and secure local storage to address these '
    'concerns.\n\n'
    'Quality Assurance: The arxiv paper [8] on personalised lesson plan assessment provides evaluation criteria that '
    'have informed ClassAI\'s content validation and audit logging mechanisms.\n\n'
    'Offline Capability: While not explicitly discussed in the reviewed papers, the practical requirements of the '
    'Nigerian educational context demand offline-first architecture, which ClassAI implements through its local '
    'SQLite database, credit system, and synchronisation engine.'
)
run.font.size = Pt(12)
run.font.name = 'Times New Roman'

doc.add_page_break()

# ════════════════════════════════════════════════════════════════════
# CHAPTER 3: METHODOLOGY
# ════════════════════════════════════════════════════════════════════
p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
run = p.add_run('CHAPTER 3\nMETHODOLOGY')
run.bold = True
run.font.size = Pt(14)

# 3.1 Research Design
p = doc.add_paragraph()
run = p.add_run('3.1 Research Design')
run.bold = True
run.font.size = Pt(12)

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
run = p.add_run(
    'This project adopted a Design Science Research (DSR) methodology, which is a well-established research '
    'paradigm in computer science and information systems that focuses on the development and evaluation of '
    'innovative artefacts to solve identified problems. The DSR approach was selected because it accommodates both '
    'the technical development of the ClassAI system (the artefact) and the systematic review of research literature '
    'that informs the design.\n\n'
    'The project followed Peffers et al.\'s [15] six-step DSR process: (1) problem identification and motivation — '
    'identifying the challenge of lesson note preparation in Nigerian secondary schools; (2) definition of solution '
    'objectives — specifying the requirements for an AI-powered lesson notes generator; (3) design and development '
    '— building the ClassAI system using Flutter and Dart; (4) demonstration — showing how the system generates '
    'curriculum-aligned lesson notes; (5) evaluation — mapping system features to findings from research literature; '
    'and (6) communication — documenting the system design, implementation, and findings in this report.'
)
run.font.size = Pt(12)
run.font.name = 'Times New Roman'

# 3.2 System Architecture and Design
p = doc.add_paragraph()
run = p.add_run('3.2 System Architecture and Design')
run.bold = True
run.font.size = Pt(12)

# 3.2.1 Overall Architecture
p = doc.add_paragraph()
run = p.add_run('3.2.1 Overall Architecture')
run.bold = True
run.font.size = Pt(12)

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
run = p.add_run(
    'ClassAI adopts a three-tier architecture consisting of a presentation tier (Flutter cross-platform UI), a logic '
    'tier (Dart services and providers), and a data tier (local SQLite database and Supabase cloud backend). This '
    'architecture ensures separation of concerns, maintainability, and the ability to operate independently of '
    'network connectivity.\n\n'
    'The presentation layer is built using Flutter\'s widget-based UI framework with Riverpod for state management. '
    'Key screens include the Dashboard, Lesson Editor, Exam Editor, Scheme of Work, Settings, Admin Dashboard, '
    'Payment, and Vault. The router is implemented using go_router for declarative routing with deep link support.\n\n'
    'The logic tier comprises service classes that encapsulate business logic: AiService for prompt construction and '
    'LLM communication, SyncService for data synchronisation, AcademicCalendarService for term-aware week '
    'calculations, CreditService for subscription management, PaymentService for Paystack integration, ExportService '
    'for data export to CSV/PDF, SecurityService for encryption and authentication operations, VacuumService for '
    'safe database maintenance, PdfService for PDF generation with caching, and MergeEngine for three-way data '
    'conflict resolution.\n\n'
    'The data tier uses Drift ORM for local SQLite database management with 20 database tables covering lessons, '
    'subjects, teachers, schools, terms, schemes of work, exams, sync queue, audit logs, and security configurations. '
    'Supabase provides the cloud PostgreSQL database, real-time subscriptions, and authentication services.'
)
run.font.size = Pt(12)
run.font.name = 'Times New Roman'

# Figure 3.1 caption
p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
run = p.add_run('Fig. 3.1. High-level system architecture diagram showing the three tiers (Presentation — Flutter UI, '
                'Logic — Dart services, Data — local SQLite + Supabase cloud).')
run.italic = True
run.font.size = Pt(10)
run.font.name = 'Times New Roman'

# Architecture diagram as text table
p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
run = p.add_run('[Architecture Diagram Placeholder — Three-tier box-and-arrow diagram showing '
                'Presentation (Flutter UI) → Logic (Dart Services) → Data (SQLite + Supabase)]')
run.font.size = Pt(10)
run.font.name = 'Times New Roman'
run.italic = True

# 3.2.2 AI Generation Workflow
p = doc.add_paragraph()
run = p.add_run('3.2.2 AI Generation Workflow')
run.bold = True
run.font.size = Pt(12)

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
run = p.add_run(
    'The AI generation workflow in ClassAI follows a structured pipeline informed by the curriculum-informed AI '
    'approach advocated by Imagine Learning [2] and the generative AI alignment framework by Liu et al. [3]:\n\n'
    '1. Prompt Construction: The system constructs a detailed prompt using the PromptTemplates class, incorporating '
    'subject, curriculum type, class level, week number, topic, difficulty level, and Bloom\'s Taxonomy verbs '
    'specified by the teacher.\n\n'
    '2. Injection Detection: The constructed prompt is scanned for prompt injection attempts using '
    'SanitizationUtils.findInjections(), which detects SQL injection patterns, system prompt override attempts, '
    'and other malicious inputs.\n\n'
    '3. Token Management: The prompt is truncated if it exceeds 4,096 tokens using TokenCounter.truncateIfNeeded(), '
    'ensuring it fits within the LLM\'s context window while preserving essential curriculum metadata.\n\n'
    '4. Primary Generation: The system sends the sanitised prompt to the DeepSeek API. If successful, the response '
    'is parsed and returned.\n\n'
    '5. Automatic Failover: If DeepSeek API returns an error (network failure, rate limiting, service outage), the '
    'system automatically retries the request using the Gemini API, ensuring continuous service availability.\n\n'
    '6. Response Parsing: The AI response is stripped of markdown wrappers (code fences, introductory/concluding '
    'text) and parsed as JSON. The structured output includes learning objectives, key vocabulary, materials, lesson '
    'presentation, assessment, and homework sections.\n\n'
    '7. Audit Logging: Each generation event is logged with teacher ID, school ID, topic, and timestamp for '
    'accountability and usage tracking.'
)
run.font.size = Pt(12)
run.font.name = 'Times New Roman'

# Figure 3.2 caption
p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
run = p.add_run('Fig. 3.2. AI generation workflow diagram (Teacher Input → Prompt Construction → Injection Check → '
                'DeepSeek API → [fallback to Gemini] → Response Parsing → Structured JSON → Editor).')
run.italic = True
run.font.size = Pt(10)
run.font.name = 'Times New Roman'

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
run = p.add_run('[AI Workflow Diagram Placeholder — Flowchart showing Teacher Input → Prompt Construction → '
                'Injection Check → DeepSeek API → fallback to Gemini → Response Parsing → Structured JSON → Editor]')
run.font.size = Pt(10)
run.font.name = 'Times New Roman'
run.italic = True

# 3.2.3 Offline-First Synchronisation Pipeline
p = doc.add_paragraph()
run = p.add_run('3.2.3 Offline-First Synchronisation Pipeline')
run.bold = True
run.font.size = Pt(12)

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
run = p.add_run(
    'ClassAI\'s synchronisation pipeline implements a robust offline-first strategy designed for the intermittent '
    'connectivity typical of Nigerian schools. The SyncService manages the full sync lifecycle through a state '
    'machine with the following states: idle, acquiringSession, biometricPrompt, sessionKeyDecrypt, pulling, '
    'merging, savingConflicts, pushing, applyingCredits, emergencySave, forcedLogout, updatingMetadata, '
    'replayingRealtime, and backoff.\n\n'
    'The sync system implements exponential backoff for retries (starting at 5 seconds, doubling up to 5 retries), '
    'payload compression for transfers exceeding 50 KB, and batch-size reduction (from 10 to 5 records per batch) '
    'optimised for 2G/3G network conditions. The MergeEngine supports three-way merging (local, remote, base) with '
    'configurable field-level strategies including Last-Writer-Wins (LWW), union, keep local, keep remote, and '
    'manual resolution.'
)
run.font.size = Pt(12)
run.font.name = 'Times New Roman'

# 3.2.4 Database Schema
p = doc.add_paragraph()
run = p.add_run('3.2.4 Database Schema')
run.bold = True
run.font.size = Pt(12)

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
run = p.add_run(
    'The ClassAI database schema comprises 20 tables designed to support all system functionalities:\n\n'
    'lessons — Stores generated lesson notes with encrypted content, subject, class level, week, topic, difficulty, '
    'curriculum type, Bloom\'s Taxonomy verbs, and status (draft/published/archived).\n'
    'subjects — Defines available subjects per curriculum with 18 NERDC core subjects pre-configured.\n'
    'teachers — Teacher profiles with authentication data, device registration, and token management.\n'
    'schools — School information, subscription tier, expiry date, and configuration settings.\n'
    'terms — Academic term definitions with start/end dates, term names, and school association.\n'
    'scheme_of_work — Schedule of topics per term with week-by-week planning.\n'
    'exams — Generated examination questions with MCQ, theory, and subjective question types.\n'
    'exams_dao, lessons_dao, subjects_dao, teachers_dao, schools_dao, terms_dao, scheme_of_work_dao — Data Access '
    'Objects for database operations.\n'
    'sync_queue — Pending synchronisation entries with retry tracking and conflict resolution.\n'
    'audit_logs — Security and usage audit trail for accountability.\n'
    'security_config — Encryption keys, credit balances, daily generation counters.\n'
    'vault_items — Encrypted sensitive data storage for secure content publishing.\n'
    'payment_events — Transaction records for Paystack payment tracking.\n'
    'pdf_cache — Cached PDF generation outputs for performance optimisation.\n'
    'teacher_devices — Registered device tracking for multi-device sync.\n'
    'teacher_subjects — Subject assignment mapping for teachers.\n'
    'conflicts — Unresolved sync conflicts requiring manual resolution.\n'
    'progress_logs — Teacher progress tracking across curriculum topics.\n'
    'pending_recovery_requests — Password recovery workflow management.\n'
    'recovery_codes — One-time recovery codes for account access restoration.'
)
run.font.size = Pt(12)
run.font.name = 'Times New Roman'

# 3.2.5 Security Architecture
p = doc.add_paragraph()
run = p.add_run('3.2.5 Security Architecture')
run.bold = True
run.font.size = Pt(12)

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
run = p.add_run(
    'ClassAI implements a multi-layered security architecture: (1) AES-256-GCM encryption using the cryptography '
    'Dart package for lesson content at rest; (2) Argon2id key derivation function with configurable memory '
    '(32,768 KB), iterations (3), and parallelism (2) parameters; (3) Flutter Secure Storage for protecting '
    'sensitive tokens; (4) biometric authentication via local_auth for accessing encrypted content; (5) session '
    'management with token refresh and token_version_mismatch detection for identifying logins on other devices; '
    'and (6) Sentry integration for error monitoring and crash reporting.'
)
run.font.size = Pt(12)
run.font.name = 'Times New Roman'

# 3.3 Implementation Details
p = doc.add_paragraph()
run = p.add_run('3.3 Implementation Details')
run.bold = True
run.font.size = Pt(12)

p = doc.add_paragraph()
run = p.add_run('3.3.1 Development Environment')
run.bold = True
run.font.size = Pt(12)

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
run = p.add_run(
    'The system was developed using the Flutter SDK (version 3.4.0) with Dart programming language. The minimum '
    'target SDK for Android is API 21 (Android 5.0), and the minimum iOS deployment target is iOS 12.0. Build '
    'automation was managed through Gradle (Android) and CocoaPods (iOS). The project also includes web and desktop '
    '(Linux, macOS, Windows) platform support through Flutter\'s multi-platform compilation.'
)
run.font.size = Pt(12)
run.font.name = 'Times New Roman'

# 3.3.2 Key Dependencies
p = doc.add_paragraph()
run = p.add_run('3.3.2 Key Dependencies')
run.bold = True
run.font.size = Pt(12)

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
run = p.add_run('The following key dependencies were used in the project implementation:')
run.font.size = Pt(12)
run.font.name = 'Times New Roman'

# Dependencies table WITH GRIDLINES (NO caret symbols)
dep_headers = ['Package', 'Version', 'Purpose']
dep_rows = [
    ('flutter_riverpod', '3.3.1', 'State management'),
    ('go_router', '17.2.3', 'Declarative routing'),
    ('drift', '2.31.0', 'SQLite ORM for local database'),
    ('supabase_flutter', '2.12.4', 'Supabase cloud backend client'),
    ('cryptography', '2.9.0', 'AES-256-GCM encryption'),
    ('flutter_secure_storage', '10.2.0', 'Secure token storage'),
    ('local_auth', '3.0.1', 'Biometric authentication'),
    ('sentry_flutter', '8.14.2', 'Error monitoring and crash reporting'),
    ('app_links', '6.3.2', 'Deep link support'),
    ('paystack_client', 'latest', 'Payment processing'),
    ('pdf', 'latest', 'PDF generation'),
    ('csv', 'latest', 'CSV export'),
]
add_table_with_data(dep_headers, dep_rows)

# 3.3.3 Project Structure
p = doc.add_paragraph()
run = p.add_run('3.3.3 Project Structure')
run.bold = True
run.font.size = Pt(12)

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
run = p.add_run(
    'The ClassAI project follows a feature-first directory structure under the lib/ directory:\n\n'
    'core/ — Shared code including constants, database (tables, DAOs), services, providers, theme, utilities, '
    'and widgets.\n'
    'features/ — Feature-specific code organised by domain: admin, auth, credit, dashboard, exam, lesson, payment, '
    'scheme_of_work, settings, and vault.\n'
    'router/ — Application routing configuration using go_router with authentication guards.\n'
    'test/ — Unit and widget tests covering AI services, authentication, sync, encryption, credits, UI components, '
    'and database operations (30+ test files).'
)
run.font.size = Pt(12)
run.font.name = 'Times New Roman'

# 3.4 Technology Stack
p = doc.add_paragraph()
run = p.add_run('3.4 Technology Stack')
run.bold = True
run.font.size = Pt(12)

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
run = p.add_run(
    'The technology stack for ClassAI was selected based on requirements for cross-platform deployment, offline '
    'capability, security, and AI integration.'
)
run.font.size = Pt(12)
run.font.name = 'Times New Roman'

# Technology stack table WITH GRIDLINES
tech_headers = ['Tier', 'Technology', 'Purpose']
tech_rows = [
    ('Presentation', 'Flutter 3.4.0 + Dart', 'Cross-platform UI framework'),
    ('State Management', 'Riverpod 3.3.1', 'Application state management'),
    ('Local Database', 'SQLite via Drift ORM 2.31.0', 'Offline data storage'),
    ('Cloud Backend', 'Supabase (PostgreSQL)', 'Cloud sync, auth, real-time'),
    ('AI Provider 1', 'DeepSeek API', 'Primary LLM for content generation'),
    ('AI Provider 2', 'Gemini API', 'Fallback LLM for content generation'),
    ('Encryption', 'AES-256-GCM + Argon2id', 'Data-at-rest encryption'),
    ('Payments', 'Paystack API', 'Subscription payment processing'),
    ('Error Monitoring', 'Sentry', 'Crash reporting and diagnostics'),
    ('Routing', 'go_router', 'Declarative navigation with deep links'),
]
add_table_with_data(tech_headers, tech_rows)

doc.add_page_break()

# ════════════════════════════════════════════════════════════════════
# CHAPTER 4: SYSTEM DEVELOPMENT AND RESULTS
# ════════════════════════════════════════════════════════════════════
p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
run = p.add_run('CHAPTER 4\nSYSTEM DEVELOPMENT AND RESULTS')
run.bold = True
run.font.size = Pt(14)

# 4.1 System Implementation Results
p = doc.add_paragraph()
run = p.add_run('4.1 System Implementation Results')
run.bold = True
run.font.size = Pt(12)

p = doc.add_paragraph()
run = p.add_run('4.1.1 Functional Modules Implementation')
run.bold = True
run.font.size = Pt(12)

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
run = p.add_run(
    'The ClassAI system has been successfully implemented with all planned functional modules operational. The '
    'application compiles and runs on Android, iOS, Web, and desktop platforms (Linux, macOS, Windows) with a '
    'single Dart codebase, demonstrating the effectiveness of Flutter\'s cross-platform capabilities. The following '
    'subsections present the implementation status of each major module.\n\n'
    'Authentication Module: The auth system supports email/password registration and login with Supabase '
    'authentication, email verification, password reset with recovery codes, email OTP verification (via Gmail SMTP), '
    'biometric authentication integration, and session management with token refresh. The module also implements '
    'login on other device detection (token_version_mismatch) and automatic logout on security violations. The '
    'implementation is located in auth_service.dart covering login, signup, password recovery, email verification, '
    'and admin recovery workflows.\n\n'
    'Lesson Generation Module: The AI-powered lesson generation system successfully generates structured lesson '
    'notes through the curriculum-informed prompt pipeline. The PromptTemplates class constructs prompts incorporating '
    'subject, curriculum type, class level, week number, topic, difficulty, and Bloom\'s Taxonomy verbs. The '
    'AiService class manages the full generation lifecycle including injection detection, token truncation, DeepSeek '
    'primary call, Gemini fallback, markdown stripping, and JSON parsing. The system supports all three supported '
    'curricula (NERDC, Cambridge, CCSS) with appropriate prompt customisation.\n\n'
    'Academic Calendar Engine: The AcademicCalendarService implements NERDC trimester-aware week numbering. The '
    'system recognises the standard Nigerian academic calendar: First Term (September-December), Second Term '
    '(January-April), and Third Term (May-July). Week numbering resets at the start of each term (Week 1). The '
    'service also calculates academic years using the September-August cycle typical of Nigerian schools.\n\n'
    'Offline Credit System: The credit system implements the specified offline credit allocation per subscription '
    'tier: Free (3 credits), Basic (5 credits), Standard (10 credits), and Elite (20 credits). Credit deduction '
    'follows the "batch-write-before-network" pattern where the batch ID is written to SQLite before any network '
    'call, ensuring atomicity and preventing double-spending. The CreditService handles credit spending, offline '
    'deduction, and sync queue management.\n\n'
    'Data Export Module: The ExportService supports export of lesson data in CSV format with columns: Title, Week, '
    'Topic, Objectives, Materials, Assessment, and Created. The PdfService handles PDF generation with caching, '
    'watermarking for free-tier users, and low-storage protection that blocks generation when storage falls below '
    '100 MB critical threshold.\n\n'
    'Payment Integration: The PaymentService integrates with the Paystack API for subscription management. It '
    'supports payment initialisation with checkout URL generation, payment confirmation via webhook or polling, '
    'activation code generation, and subscription tier management. The pricing structure supports four tiers with '
    'annual billing in Nigerian Naira: Basic (NGN 49,999/year), Standard (NGN 99,999/year), and Elite '
    '(NGN 249,999/year).\n\n'
    'Database and Synchronisation: The SyncService implements the comprehensive offline-first synchronisation '
    'engine. It manages session acquisition, biometric authentication for key decryption, data pulling and pushing, '
    'three-way merging via MergeEngine, and conflict storage for manual resolution. The system supports payload '
    'compression, batch size optimisation for 2G/3G networks, and exponential backoff for retry management.'
)
run.font.size = Pt(12)
run.font.name = 'Times New Roman'

# 4.1.2 System Configuration and Requirements
p = doc.add_paragraph()
run = p.add_run('4.1.2 System Configuration and Requirements')
run.bold = True
run.font.size = Pt(12)

# Requirements table WITH GRIDLINES
req_headers = ['Component', 'Minimum Requirement', 'Recommended']
req_rows = [
    ('Operating System', 'Android 5.0 (API 21) / iOS 12.0', 'Android 8.0+ / iOS 14.0+'),
    ('RAM', '2 GB', '4 GB or more'),
    ('Storage', '100 MB free space', '500 MB free space'),
    ('Internet', 'Periodic (for sync only)', 'Broadband/4G for real-time sync'),
    ('Processor', 'ARM Cortex-A53 or equivalent', 'ARM Cortex-A73 or better'),
    ('Display', '5-inch screen', '7-inch tablet or larger'),
]
add_table_with_data(req_headers, req_rows)

# 4.2 Feature Mapping to Research Literature
p = doc.add_paragraph()
run = p.add_run('4.2 Feature Mapping to Research Literature')
run.bold = True
run.font.size = Pt(12)

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
run = p.add_run(
    'Table 4.1 below summarises how specific features implemented in ClassAI map to findings and recommendations '
    'from the ten research papers reviewed in Chapter 2.'
)
run.font.size = Pt(12)
run.font.name = 'Times New Roman'

# Table 4.1 — Feature Mapping WITH MODIFIED CITATIONS
p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
run = p.add_run('TABLE 4.1')
run.bold = True
run.font.size = Pt(10)

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
run = p.add_run('Feature mapping of ClassAI system features to research literature.')
run.italic = True
run.font.size = Pt(10)

fm_headers = ['ClassAI Feature', 'Informed by (Paper/Reference)']
fm_rows = [
    ('Curriculum-aware prompt templates embedding subject, curriculum type, class, week, topic, difficulty, and Bloom\'s Taxonomy', '[2]'),
    ('Structured JSON output schema with objectives, vocabulary, materials, presentation, assessment, homework', '[3]'),
    ('NERDC trimester-aware academic calendar and scheme of work generation', '[4]'),
    ('Interactive lesson editor requiring active teacher parameter input and content review', '[5]'),
    ('Six-step lesson generation pipeline: objectives, parameters, generate, review, assess, finalise', '[6]'),
    ('AES-256-GCM encryption, Argon2id key derivation, secure local storage', '[7]'),
    ('Content validation, markdown stripping, audit logging for quality assurance', '[8]'),
    ('Teacher-controlled generation parameters, editable output, audit transparency', '[9]'),
    ('Human-AI collaboration design: AI as assistant/augmenter, teacher as final decision-maker', '[10]'),
    ('Structured lesson format with parameter specification interface, CSV/PDF export', '[11]'),
    ('Multi-curriculum support (NERDC, Cambridge, CCSS) with version tracking', 'General design principle from system reliability and connectivity requirements'),
    ('Offline-first architecture with local SQLite, credit system, conflict-free sync', 'General design principle from Nigerian educational context requirements'),
]
add_table_with_data(fm_headers, fm_rows)

# 4.3 Discussion of Findings
p = doc.add_paragraph()
run = p.add_run('4.3 Discussion of Findings')
run.bold = True
run.font.size = Pt(12)

p = doc.add_paragraph()
run = p.add_run('4.3.1 Curriculum-Aware Content Generation')
run.bold = True
run.font.size = Pt(12)

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
run = p.add_run(
    'The implementation of curriculum-aware prompt templates in ClassAI demonstrates how findings from the '
    'Imagine Learning white paper [2] can be operationalised in a practical system. By embedding curriculum '
    'metadata — including subject, class level, curriculum type, week number, topic, difficulty, and Bloom\'s '
    'Taxonomy verbs — directly into the LLM prompt, the system guides the AI to generate content that is explicitly '
    'aligned with curriculum specifications. This approach aligns with Liu et al.\'s [3] findings that structured '
    'prompts significantly improve the relevance and accuracy of AI-generated educational content.'
)
run.font.size = Pt(12)
run.font.name = 'Times New Roman'

p = doc.add_paragraph()
run = p.add_run('4.3.2 Human-AI Collaboration in Practice')
run.bold = True
run.font.size = Pt(12)

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
run = p.add_run(
    'The Human-AI Collaboration Framework proposed by Chan, Kim et al. [10] provides a useful lens for understanding '
    'ClassAI\'s design philosophy. The system operates primarily in the "AI as assistant" mode — handling the routine, '
    'time-intensive task of generating structured, curriculum-aligned lesson content from teacher-provided '
    'parameters. This frees teachers to focus on higher-value activities such as content customisation, '
    'contextualisation, and instructional delivery. The system also functions in "AI as augmenter" mode by '
    'suggesting Bloom\'s Taxonomy-aligned cognitive levels, vocabulary lists, and assessment strategies.\n\n'
    'The preservice teachers study [5] warning about over-reliance on AI-generated content informed the design of '
    'ClassAI\'s interactive workflow. The system requires active teacher input at every stage — from parameter '
    'specification to content review and customisation — rather than offering a one-click "generate and accept" '
    'flow. This design choice encourages the critical engagement with AI-generated content that the study recommends.'
)
run.font.size = Pt(12)
run.font.name = 'Times New Roman'

p = doc.add_paragraph()
run = p.add_run('4.3.3 Structured Content Generation')
run.bold = True
run.font.size = Pt(12)

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
run = p.add_run(
    'The structured JSON output schema implemented in ClassAI — with explicit sections for learning objectives, '
    'key vocabulary, materials, lesson presentation, assessment, and homework — addresses the teacher preference '
    'for well-structured AI output identified by Del Valle [11]. The schema ensures completeness (all essential '
    'lesson components are included) and consistency (all generated lessons follow the same structure, facilitating '
    'comparison and quality assurance). This structured approach also enables the system to validate generated '
    'content, identify missing sections, and provide meaningful feedback to teachers.'
)
run.font.size = Pt(12)
run.font.name = 'Times New Roman'

p = doc.add_paragraph()
run = p.add_run('4.3.4 Security and Privacy Considerations')
run.bold = True
run.font.size = Pt(12)

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
run = p.add_run(
    'The security architecture of ClassAI addresses the data protection concerns raised by Mahafdah et al. [7]. '
    'The use of AES-256-GCM encryption ensures that lesson content is protected at rest, while Argon2id key '
    'derivation provides robust protection against brute-force attacks on teacher passwords. The integration of '
    'biometric authentication adds an additional layer of security for sensitive operations. These measures are '
    'particularly important given the sensitive nature of educational data and the requirements of the Nigeria '
    'Data Protection Regulation (NDPR) 2019 [16].'
)
run.font.size = Pt(12)
run.font.name = 'Times New Roman'

p = doc.add_paragraph()
run = p.add_run('4.3.5 Offline-First Architecture for the Nigerian Context')
run.bold = True
run.font.size = Pt(12)

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
run = p.add_run(
    'The offline-first architecture of ClassAI addresses a critical requirement for educational technology '
    'deployment in Nigeria — the ability to function without reliable internet connectivity. The local SQLite '
    'database (via Drift ORM) stores all application data, including generated lesson notes, user accounts, and '
    'configuration settings. The credit system allows teachers to generate content offline using pre-allocated '
    'credits that are synchronised when connectivity is restored. The sync service manages data synchronisation '
    'in the background, handling conflicts through three-way merging and providing visual feedback through the '
    'sync indicator widget.'
)
run.font.size = Pt(12)
run.font.name = 'Times New Roman'

doc.add_page_break()

# ════════════════════════════════════════════════════════════════════
# CHAPTER 5: SUMMARY, RECOMMENDATION AND CONCLUSION
# ════════════════════════════════════════════════════════════════════
p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
run = p.add_run('CHAPTER 5\nSUMMARY, RECOMMENDATION AND CONCLUSION')
run.bold = True
run.font.size = Pt(14)

# 5.1 Summary of the Study
p = doc.add_paragraph()
run = p.add_run('5.1 Summary of the Study')
run.bold = True
run.font.size = Pt(12)

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
run = p.add_run(
    'This project set out to design and develop ClassAI, an AI-powered, curriculum-aware lesson notes generator '
    'for Nigerian secondary schools. The work was motivated by the identified gap in standardised, high-quality '
    'lesson note preparation facing Nigerian teachers, compounded by large class sizes, limited resources, '
    'insufficient planning time, technological constraints, and the absence of localised AI-powered educational '
    'tools tailored to the NERDC curriculum.\n\n'
    'The project employed a Design Science Research methodology, resulting in the development of a fully functional '
    'cross-platform mobile application built with Flutter and Dart. The system architecture integrates a local '
    'SQLite database (via Drift ORM) for offline operation, a Supabase cloud backend for synchronisation and '
    'authentication, and a dual-provider AI engine (DeepSeek with Gemini fallback) for content generation. The '
    'system supports three curricula (NERDC, Cambridge, CCSS), 18 core Nigerian secondary school subjects, '
    'Bloom\'s Taxonomy-aligned cognitive level targeting, and a secure offline-first credit system integrated with '
    'Paystack payment processing.\n\n'
    'A comprehensive review of ten recent research papers on AI in education was conducted, covering '
    'curriculum-informed AI, generative AI-powered educational alignment, AI in curriculum development, '
    'AI-assisted lesson generation, human-AI collaboration in education, and personalised learning. Findings from '
    'these papers directly informed the design and feature set of ClassAI, ensuring that the system is grounded in '
    'current research while addressing the practical requirements of the Nigerian educational context.'
)
run.font.size = Pt(12)
run.font.name = 'Times New Roman'

# 5.2 Conclusion
p = doc.add_paragraph()
run = p.add_run('5.2 Conclusion')
run.bold = True
run.font.size = Pt(12)

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
run = p.add_run(
    'This project has demonstrated that AI-powered, curriculum-aware lesson notes generation is both feasible and '
    'implementable for the Nigerian secondary education context. The ClassAI system successfully addresses the key '
    'challenges of lesson note preparation by leveraging large language models to generate structured, '
    'curriculum-aligned content. The system\'s architecture — incorporating offline-first capabilities, '
    'multi-curriculum support, robust security, and a dual-provider AI failover mechanism — provides a practical '
    'template for AI-powered educational tools deployed in developing country contexts.\n\n'
    'The project makes several important contributions. First, it demonstrates how findings from contemporary AI '
    'education research can be synthesised and implemented in a practical application. Second, it presents a viable '
    'architecture for offline-first AI-powered educational tools in low-connectivity environments, addressing a '
    'critical barrier to educational technology adoption in developing countries. Third, it provides a practical '
    'integration of local payment systems (Paystack) with AI content generation, enabling a sustainable deployment '
    'model.\n\n'
    'The findings affirm that AI in education should be positioned as a teacher-assistance tool that augments rather '
    'than replaces teacher expertise. The most effective deployment model is one where AI handles the routine aspects '
    'of content generation — structure, curriculum alignment, and baseline quality — while teachers apply their '
    'professional judgment in customising, contextualising, and delivering the content to their specific students.'
)
run.font.size = Pt(12)
run.font.name = 'Times New Roman'

# 5.3 Contributions to Knowledge
p = doc.add_paragraph()
run = p.add_run('5.3 Contributions to Knowledge')
run.bold = True
run.font.size = Pt(12)

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
run = p.add_run(
    'This project makes the following contributions to knowledge:\n\n'
    '1. Development of a curriculum-aware prompt engineering framework that integrates NERDC curriculum '
    'specifications with Bloom\'s Taxonomy cognitive levels for AI-powered lesson note generation.\n\n'
    '2. Design and implementation of an offline-first AI content generation architecture specifically optimised for '
    'low-connectivity environments in developing countries, including a dual-provider AI failover mechanism, local '
    'credit management, and conflict-free data synchronisation.\n\n'
    '3. A systematic synthesis of ten recent AI education research papers, mapping their findings to implementable '
    'system features — providing a model for research-driven educational technology development.\n\n'
    '4. A replicable system architecture for integrating local payment gateways (Paystack) with AI-powered '
    'educational tools, including offline credit management and subscription-based access control.\n\n'
    '5. Comprehensive documentation of the technological, pedagogical, and contextual considerations for deploying '
    'AI-powered educational tools in Nigerian secondary schools, providing guidance for developers, educators, and '
    'policymakers.'
)
run.font.size = Pt(12)
run.font.name = 'Times New Roman'

# 5.4 Recommendations
p = doc.add_paragraph()
run = p.add_run('5.4 Recommendations')
run.bold = True
run.font.size = Pt(12)

p = doc.add_paragraph()
run = p.add_run('5.4.1 Recommendations for Teachers')
run.bold = True
run.font.size = Pt(12)

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
run = p.add_run(
    'Adopt ClassAI as a lesson planning assistant to reduce preparation time while maintaining content quality and '
    'curriculum alignment.\n'
    'Regularly review and customise AI-generated content to reflect local contexts, student abilities, and available '
    'teaching resources.\n'
    'Use the Bloom\'s Taxonomy targeting feature to design lessons that address multiple cognitive levels and promote '
    'higher-order thinking skills.'
)
run.font.size = Pt(12)
run.font.name = 'Times New Roman'

p = doc.add_paragraph()
run = p.add_run('5.4.2 Recommendations for School Administrators')
run.bold = True
run.font.size = Pt(12)

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
run = p.add_run(
    'Deploy ClassAI across subject departments to standardise lesson note quality and facilitate instructional '
    'supervision.\n'
    'Provide training sessions for teachers on effective use of AI-assisted lesson planning tools.\n'
    'Invest in offline-capable devices (tablets, laptops) for teachers to maximise the benefits of the system\'s '
    'offline capabilities.'
)
run.font.size = Pt(12)
run.font.name = 'Times New Roman'

p = doc.add_paragraph()
run = p.add_run('5.4.3 Recommendations for Developers')
run.bold = True
run.font.size = Pt(12)

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
run = p.add_run(
    'Expand the system to support additional Nigerian languages and local content formats.\n'
    'Implement fine-tuned language models specifically trained on NERDC curriculum data for improved generation '
    'accuracy.\n'
    'Develop analytics dashboards for school administrators to monitor content generation patterns and quality '
    'metrics.\n'
    'Conduct empirical evaluation studies with teachers and students to validate system effectiveness in real '
    'classroom settings.'
)
run.font.size = Pt(12)
run.font.name = 'Times New Roman'

# NOTE: Section 5.5 Limitations of the Study has been REMOVED (moved to Chapter 1)

# 5.5 Suggestions for Future Research (renumbered from 5.6)
p = doc.add_paragraph()
run = p.add_run('5.5 Suggestions for Future Research')
run.bold = True
run.font.size = Pt(12)

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
run = p.add_run(
    'Future research directions emerging from this project include:\n\n'
    'Empirical Evaluation: Conduct controlled studies with teachers and students to assess the impact of '
    'AI-generated lesson notes on teaching efficiency, content quality, and student learning outcomes.\n\n'
    'Fine-Tuned Models: Investigate the development of fine-tuned language models specifically trained on NERDC '
    'curriculum documents and Nigerian educational content for improved generation accuracy.\n\n'
    'Multilingual Support: Extend the system to support indigenous Nigerian languages (Hausa, Igbo, Yoruba) for '
    'lesson generation in language-intensive subjects.\n\n'
    'Adaptive Personalisation: Research adaptive algorithms that dynamically adjust content difficulty based on '
    'student performance data and individual learning needs.\n\n'
    'Cross-Curriculum Analysis: Compare the effectiveness of AI-generated lesson notes across different curricula '
    '(NERDC, Cambridge, CCSS) to identify best practices for each.\n\n'
    'Teacher Professional Development: Investigate the potential of AI-powered lesson planning tools as platforms '
    'for teacher professional development and pedagogical skill enhancement.'
)
run.font.size = Pt(12)
run.font.name = 'Times New Roman'

doc.add_page_break()

# ════════════════════════════════════════════════════════════════════
# REFERENCES
# ════════════════════════════════════════════════════════════════════
p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
run = p.add_run('REFERENCES')
run.bold = True
run.font.size = Pt(14)

references = [
    '[1] National Bureau of Statistics, "Statistical report on primary and secondary education in Nigeria," Federal Government of Nigeria, 2023. [Online]. Available: https://nigerianstat.gov.ng/',
    '[2] Imagine Learning, "Curriculum-informed AI," White Paper, Apr. 2025. [Online]. Available: https://www.imaginelearning.com/wp-content/uploads/2025/04/1620957897_Curriculum_Informed_AI_White_Paper_DIGITAL.pdf',
    '[3] S. Liu, A. Mendoza, T. Martin, and V. Miori, "Generative AI-powered educational alignment," in Proc. ACM Int. Conf. Distance Educ. Learn. (ICDEL), 2024. doi: 10.1145/3675812.3675874.',
    '[4] A. Mohamed Sapawi and N. Nik Yusoff, "Artificial intelligence in curriculum development," J. Curriculum Stud. Res., 2025. [Online]. Available: https://curriculumstudies.org/index.php/CS/article/view/635',
    '[5] Preservice Teachers Study, "Exploring the impact of generative AI on curriculum design and instruction: A study with preservice teachers," ResearchGate, 2026. [Online]. Available: https://www.researchgate.net/publication/399686182_Exploring_the_Impact_of_Generative_AI_on_Curriculum_Design_and_Instruction_A_Study_With_Preservice_Teachers',
    '[6] Wiley, "AI-assisted lesson generation in medical and professional education: A practical guide," 2026. [Online]. Available: https://onlinelibrary.wiley.com/doi/10.1002/mef2.70018',
    '[7] K. Mahafdah, M. Bouallegue, and B. Bouallegue, "Enhancing e-learning through AI," PeerJ Comput. Sci., 2024. [Online]. Available: https://pmc.ncbi.nlm.nih.gov/articles/PMC11784796/',
    '[8] arxiv, "Assessing the impact of AI-generated personalized lesson plans," 2025. [Online]. Available: https://arxiv.org/pdf/2510.19866',
    '[9] NCBI PMC, "Designing and evaluating an AI-integrated curriculum," 2025. [Online]. Available: https://www.ncbi.nlm.nih.gov/pmc/articles/PMC12189063/',
    '[10] J. Chan, S. Kim et al., "Learning design to advance human-AI collaboration in K-12 education," Old Dominion Univ. Digital Commons, 2025. [Online]. Available: https://digitalcommons.odu.edu/stemps_fac_pubs/419/',
    '[11] J. M. Del Valle, "Use of generative AI in writing lesson plans," Int. J. Soc. Sci. Humanities Res., vol. 4, no. 7, 2025. doi: 10.58806/ijsshmr.2025.v4i7n02.',
    '[12] J. Piaget, The Psychology of the Child. New York, NY, USA: Basic Books, 1972.',
    '[13] L. S. Vygotsky, Mind in Society: The Development of Higher Psychological Processes. Cambridge, MA, USA: Harvard Univ. Press, 1978.',
    '[14] P. Mishra and M. J. Koehler, "Technological pedagogical content knowledge: A framework for teacher knowledge," Teachers College Record, vol. 108, no. 6, pp. 1017–1054, 2006.',
    '[15] K. Peffers, T. Tuunanen, M. A. Rothenberger, and S. Chatterjee, "A design science research methodology for information systems research," J. Manage. Inf. Syst., vol. 24, no. 3, pp. 45–77, 2007.',
    '[16] Nigeria Data Protection Regulation, 2019. [Online]. Available: https://ndpr.nitda.gov.ng/',
    '[17] Teachers Registration Council of Nigeria, Professional Standards for Nigerian Teachers, TRCN Publications, 2022.',
]

for ref in references:
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
    p.paragraph_format.left_indent = Cm(1.27)
    p.paragraph_format.first_line_indent = Cm(-1.27)
    run = p.add_run(ref)
    run.font.size = Pt(10)
    run.font.name = 'Times New Roman'

doc.add_page_break()

# ════════════════════════════════════════════════════════════════════
# APPENDICES
# ════════════════════════════════════════════════════════════════════
p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
run = p.add_run('APPENDICES')
run.bold = True
run.font.size = Pt(14)

# Appendix A
p = doc.add_paragraph()
run = p.add_run('Appendix A: System Configuration and Requirements')
run.bold = True
run.font.size = Pt(12)

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
run = p.add_run(
    'The ClassAI application requires the following minimum configuration for optimal performance:\n\n'
    'Mobile (Android/iOS): Minimum 2 GB RAM, 100 MB free storage, Android 5.0 or iOS 12.0 or later.\n'
    'Desktop (Windows/macOS/Linux): Minimum 4 GB RAM, 200 MB free storage.\n'
    'Web: Modern browser (Chrome 90+, Firefox 88+, Safari 14+) with JavaScript enabled.\n'
    'Internet: Periodic connectivity required for initial account creation, synchronisation, and credit purchases.'
)
run.font.size = Pt(12)
run.font.name = 'Times New Roman'

# Appendix B
doc.add_paragraph()
p = doc.add_paragraph()
run = p.add_run('Appendix B: Database Table Schema Summary')
run.bold = True
run.font.size = Pt(12)

# Schema table WITH GRIDLINES
schema_headers = ['Table Name', 'Description', 'Key Columns']
schema_rows = [
    ('lessons', 'Generated lesson notes', 'id, subject_id, class_level, week, topic, content (encrypted), status'),
    ('subjects', 'Available subjects per curriculum', 'id, name, code, curriculum_type, class_level'),
    ('teachers', 'Teacher profiles and auth', 'id, email, name, school_id, token_version'),
    ('schools', 'School information', 'id, name, address, subscription_tier, expiry_date'),
    ('terms', 'Academic term definitions', 'id, school_id, name, start_date, end_date'),
    ('scheme_of_work', 'Topic schedules', 'id, term_id, week_number, topic, objectives'),
    ('exams', 'Generated examination questions', 'id, lesson_id, question_type, content, answer_key'),
    ('sync_queue', 'Pending sync entries', 'id, table_name, record_id, operation, status, retry_count'),
    ('audit_logs', 'Event audit trail', 'id, teacher_id, event_type, details, timestamp'),
    ('vault_items', 'Encrypted secure storage', 'id, teacher_id, encrypted_data, item_type'),
]
add_table_with_data(schema_headers, schema_rows)

# Appendix C
doc.add_paragraph()
p = doc.add_paragraph()
run = p.add_run('Appendix C: Feature-to-Research Mapping Reference')
run.bold = True
run.font.size = Pt(12)

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
run = p.add_run(
    'The following table provides a quick-reference mapping of ClassAI features to the ten research papers reviewed '
    'in Chapter 2, showing how each paper informed specific system capabilities.'
)
run.font.size = Pt(12)
run.font.name = 'Times New Roman'

# Appendix C table WITH GRIDLINES
appc_headers = ['Research Paper', 'Key Finding/Contribution', 'ClassAI Feature Implemented']
appc_rows = [
    ('[2] Curriculum-Informed AI (Imagine Learning)', 'AI must be explicitly aware of curriculum standards', 'Prompt templates with curriculum metadata embedding'),
    ('[3] Educational Alignment (Liu et al.)', 'Structured prompts improve alignment accuracy', 'JSON output schema with pedagogical components'),
    ('[4] AI in Curriculum Development (Sapawi & Yusoff)', 'AI should augment, not replace human expertise', 'Academic calendar and scheme of work engine'),
    ('[5] Preservice Teachers Study', 'AI tools should encourage active teacher engagement', 'Interactive editor requiring parameter input and review'),
    ('[6] AI-Assisted Lesson Generation (Wiley)', 'Six-step workflow for AI lesson design', 'Full generation pipeline with review cycle'),
    ('[7] Enhancing E-Learning Through AI (Mahafdah et al.)', 'Data security is critical in AI education systems', 'AES-256-GCM encryption and secure vault'),
    ('[8] Impact of AI-Generated Lesson Plans (arxiv)', 'AI plans match human quality in structure', 'Content validation and audit logging'),
    ('[9] Designing AI-Integrated Curriculum (NCBI PMC)', 'Participatory design with teacher involvement', 'Teacher-controlled parameters and editable output'),
    ('[10] Human-AI Collaboration (Chan, Kim et al.)', 'Three modes: assistant, augmenter, explorer', 'AI as assistant/augmenter workflow'),
    ('[11] Use of GenAI in Writing Lesson Plans (Del Valle)', 'Teachers prefer structured, parameter-driven output', 'Structured format with CSV/PDF export'),
]
add_table_with_data(appc_headers, appc_rows)

# Appendix D
doc.add_paragraph()
p = doc.add_paragraph()
run = p.add_run('Appendix D: User Interface Screenshots')
run.bold = True
run.font.size = Pt(12)

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
run = p.add_run(
    'This appendix presents selected screenshots from the latest ClassAI build, covering the dashboard, scheme of '
    'work generator, lesson editor, and examination workflows. The figures document the core user-facing modules '
    'described in Chapter 4.'
)
run.font.size = Pt(12)
run.font.name = 'Times New Roman'

# Screenshot placeholders
screenshots = [
    ('Figure D.1:', 'Dashboard Overview in Dark Theme — Shows the main dashboard with navigation, credit counter, sync indicator, and quick-access tiles for lesson generation, exams, and settings.'),
    ('Figure D.2:', 'Scheme of Work Generator — Displays the term selection, week-by-week topic planning interface, and curriculum progress tracking.'),
    ('Figure D.3:', 'Lesson Generation and Preview Screen — Shows the parameter input form (subject, topic, difficulty, Bloom\'s level) and the generated lesson note preview with editable sections.'),
    ('Figure D.4:', 'Dashboard Overview in Light Theme — Same dashboard as Figure D.1 but rendered in the light colour theme for accessibility.'),
    ('Figure D.5:', 'Exams List and Management Screen — Lists generated examination papers with status indicators and options for editing, exporting, or deleting.'),
    ('Figure D.6:', 'Exam Editor and Question Generation Panel — Shows the question editor with MCQ, theory, and subjective question generation capabilities.'),
]

for label, desc in screenshots:
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.LEFT
    run = p.add_run(f'{label} ')
    run.bold = True
    run.font.size = Pt(11)
    run = p.add_run(desc)
    run.font.size = Pt(11)
    run.font.name = 'Times New Roman'
    doc.add_paragraph()  # spacing

# Appendix E
p = doc.add_paragraph()
run = p.add_run('Appendix E: New Features Summary')
run.bold = True
run.font.size = Pt(12)

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
run = p.add_run(
    'The table below summarises the new user-facing features represented in the screenshots above and highlights how '
    'each one contributes to the updated system experience.'
)
run.font.size = Pt(12)
run.font.name = 'Times New Roman'

# Appendix E table WITH GRIDLINES
appe_headers = ['Feature', 'Description', 'Benefit']
appe_rows = [
    ('Dashboard Overview', 'Central navigation hub with credit counter, sync status, and quick actions', 'Provides at-a-glance system status and one-tap access to all modules'),
    ('Scheme of Work Generator', 'Term-aware week-by-week topic planning aligned with NERDC calendar', 'Simplifies curriculum planning and ensures term coverage'),
    ('Lesson Generation & Preview', 'Parameter-driven AI generation with editable preview', 'Reduces lesson planning time while maintaining teacher control'),
    ('Light/Dark Theme Support', 'Full light and dark colour themes with automatic contrast adjustment', 'Improves accessibility and user comfort during extended use'),
    ('Exams List & Management', 'Centralised exam paper repository with status tracking', 'Organises assessment materials and streamlines exam management'),
    ('Exam Editor', 'Multi-format question generation (MCQ, theory, subjective)', 'Enables comprehensive assessment creation from a single interface'),
]
add_table_with_data(appe_headers, appe_rows)

# ─── Save ────────────────────────────────────────────────────────────
output_path = 'ClassAI_Revised_Thesis.docx'
doc.save(output_path)
print(f'Document saved to: {output_path}')
print(f'File size: {os.path.getsize(output_path)} bytes')
