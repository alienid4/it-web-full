import { GoogleGenerativeAI } from '@google/generative-ai'
import { readMultipartFormData } from 'h3'

export default defineEventHandler(async (event) => {
  const config = useRuntimeConfig()
  const apiKey = config.geminiApiKey

  if (!apiKey) {
    throw createError({ statusCode: 500, message: 'GEMINI_API_KEY 未設定' })
  }

  const parts = await readMultipartFormData(event)
  const audioPart = parts?.find(p => p.name === 'audio')

  if (!audioPart || !audioPart.data) {
    throw createError({ statusCode: 400, message: '未收到音訊檔案' })
  }

  const mimeType = (audioPart.type || 'audio/mpeg') as string
  const base64Audio = audioPart.data.toString('base64')

  const genAI = new GoogleGenerativeAI(apiKey)
  const model = genAI.getGenerativeModel({ model: 'gemini-1.5-flash' })

  const result = await model.generateContent([
    {
      inlineData: {
        mimeType,
        data: base64Audio
      }
    },
    {
      text: `請完成以下兩項任務，並以 JSON 格式回傳：
1. "transcript"：完整的繁體中文逐字稿
2. "summary"：3~5 點條列式重點摘要（繁體中文）

回傳格式範例：
{
  "transcript": "...",
  "summary": "..."
}`
    }
  ])

  const text = result.response.text().trim()

  // 解析 JSON（去除 markdown code block）
  const jsonMatch = text.match(/```(?:json)?\s*([\s\S]*?)```/) || [null, text]
  const jsonStr = jsonMatch[1].trim()

  try {
    return JSON.parse(jsonStr)
  } catch {
    return { transcript: text, summary: '' }
  }
})
