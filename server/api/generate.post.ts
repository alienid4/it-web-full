import { readMultipartFormData, setResponseHeader } from 'h3'
import {
  Document, Packer, Paragraph, TextRun, HeadingLevel, AlignmentType
} from 'docx'

export default defineEventHandler(async (event) => {
  // 1. 讀取音訊檔
  const parts = await readMultipartFormData(event)
  const audioPart = parts?.find(p => p.name === 'file')

  if (!audioPart?.data) {
    throw createError({ statusCode: 400, statusMessage: '未收到音訊檔案' })
  }

  // 依副檔名決定 mimeType
  const filename = (audioPart.filename || '').toLowerCase()
  const extMimeMap: Record<string, string> = {
    mp3: 'audio/mpeg',
    mp4: 'audio/mp4',
    m4a: 'audio/mp4',
    wav: 'audio/wav',
    ogg: 'audio/ogg',
    flac: 'audio/flac',
    aac: 'audio/aac',
    webm: 'audio/webm'
  }
  const ext = filename.split('.').pop() || ''
  const mimeType = extMimeMap[ext] || 'audio/mpeg'
  const base64Audio = audioPart.data.toString('base64')

  // 2. 直接呼叫 Gemini REST API (v1beta 支援 gemini-1.5-flash 音訊)
  const apiKey = process.env.GEMINI_API_KEY
  if (!apiKey) {
    throw createError({ statusCode: 500, statusMessage: 'GEMINI_API_KEY 未設定' })
  }

  const prompt = `你是一位專業秘書。請將這段會議錄音轉錄並整理成結構化的會議記錄。內容需包含：
1. 會議主題 (自行總結)
2. 討論重點摘要 (列點)
3. 待辦事項 (Action Items - 包含負責人與期限)
請保持繁體中文輸出。

請以以下格式回傳（純文字，不要使用 Markdown）：

【會議主題】
（主題內容）

【討論重點摘要】
- （重點一）
- （重點二）
- （重點三）

【待辦事項】
- （事項）｜負責人：（姓名）｜期限：（日期）`

  const geminiRes = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-lite:generateContent?key=${apiKey}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        contents: [{
          parts: [
            { inline_data: { mime_type: mimeType, data: base64Audio } },
            { text: prompt }
          ]
        }]
      })
    }
  )

  if (!geminiRes.ok) {
    const errText = await geminiRes.text()
    throw createError({ statusCode: 502, statusMessage: `Gemini API 錯誤：${errText}` })
  }

  const geminiData = await geminiRes.json() as any
  const aiText: string = geminiData?.candidates?.[0]?.content?.parts?.[0]?.text?.trim() || ''

  if (!aiText) {
    throw createError({ statusCode: 502, statusMessage: 'Gemini 未回傳內容' })
  }

  // 3. 解析並生成 Word
  const sections = parseAIOutput(aiText)
  const doc = buildDocument(sections, aiText)
  const buffer = await Packer.toBuffer(doc)

  // 4. 回傳 docx
  setResponseHeader(event, 'Content-Type', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document')
  setResponseHeader(event, 'Content-Disposition', 'attachment; filename="meeting_minutes.docx"')

  return buffer
})

// ── 解析 AI 輸出 ────────────────────────────────────────────────
interface MeetingSections {
  topic: string
  summary: string[]
  actions: string[]
  raw: string
}

function parseAIOutput(text: string): MeetingSections {
  const topicMatch = text.match(/【會議主題】\s*([\s\S]*?)(?=【|$)/)
  const summaryMatch = text.match(/【討論重點摘要】\s*([\s\S]*?)(?=【|$)/)
  const actionMatch = text.match(/【待辦事項】\s*([\s\S]*?)(?=【|$)/)

  const extractLines = (block: string | undefined) =>
    (block || '').split('\n').map(l => l.replace(/^[-•]\s*/, '').trim()).filter(Boolean)

  return {
    topic: topicMatch?.[1]?.trim() || '（未能識別主題）',
    summary: extractLines(summaryMatch?.[1]),
    actions: extractLines(actionMatch?.[1]),
    raw: text
  }
}

// ── 建立 Word 文件 ───────────────────────────────────────────────
function buildDocument(s: MeetingSections, raw: string): Document {
  const today = new Date().toLocaleDateString('zh-TW', {
    year: 'numeric', month: 'long', day: 'numeric'
  })

  const paragraphs: Paragraph[] = [
    new Paragraph({
      text: '會議記錄',
      heading: HeadingLevel.TITLE,
      alignment: AlignmentType.CENTER,
      spacing: { after: 200 }
    }),
    new Paragraph({
      children: [new TextRun({ text: `日期：${today}`, color: '888888', size: 20 })],
      alignment: AlignmentType.CENTER,
      spacing: { after: 400 }
    }),
    new Paragraph({
      text: '一、會議主題',
      heading: HeadingLevel.HEADING_1,
      spacing: { before: 300, after: 120 }
    }),
    new Paragraph({
      children: [new TextRun({ text: s.topic, size: 24 })],
      spacing: { after: 300 }
    }),
    new Paragraph({
      text: '二、討論重點摘要',
      heading: HeadingLevel.HEADING_1,
      spacing: { before: 300, after: 120 }
    }),
    ...(s.summary.length > 0
      ? s.summary.map(item => new Paragraph({
          children: [new TextRun({ text: `• ${item}`, size: 24 })],
          spacing: { after: 80 },
          indent: { left: 360 }
        }))
      : [new Paragraph({ children: [new TextRun({ text: '（無資料）', color: '888888', size: 24 })] })]),
    new Paragraph({
      text: '三、待辦事項（Action Items）',
      heading: HeadingLevel.HEADING_1,
      spacing: { before: 300, after: 120 }
    }),
    ...(s.actions.length > 0
      ? s.actions.map((item, i) => new Paragraph({
          children: [new TextRun({ text: `${i + 1}. ${item}`, size: 24 })],
          spacing: { after: 80 },
          indent: { left: 360 }
        }))
      : [new Paragraph({ children: [new TextRun({ text: '（無待辦事項）', color: '888888', size: 24 })] })]),
    new Paragraph({
      text: '附錄：AI 完整輸出',
      heading: HeadingLevel.HEADING_2,
      spacing: { before: 600, after: 120 }
    }),
    new Paragraph({
      children: [new TextRun({ text: raw, size: 20, color: '555555' })],
      spacing: { after: 200 }
    })
  ]

  return new Document({ sections: [{ properties: {}, children: paragraphs }] })
}
