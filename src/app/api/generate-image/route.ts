import { Configuration, OpenAIApi } from "openai-edge";

const config = new Configuration({
  apiKey: process.env.OPENAI_API_KEY,
});

const openai = new OpenAIApi(config);

export async function POST(req: Request) {
  const { prompt, userId, size, quantity } = await req.json();

  if(!config.apiKey) {
    return new Response('OPENAI_API_KEY is not set', { status: 500 });
  }

  if(!prompt) {
    return new Response('prompt and size are required', { status: 400 });
  }

  try {
    const response = await openai.createImage({
      prompt: prompt,
      size: size,
      n: 1,
      user: userId,
      response_format: "b64_json",
    });

    return new Response(response.body, { status: 200 });
  } catch (error) {
    return new Response('Internal Server Error', { status: 500 });
  }
}

