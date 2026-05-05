# Secondhand clothing store inventory manager

A Flutter application built to automate inventory sorting for a secondhand clothing store. 

Instead of manual data entry, staff can take a photo of a clothing item. The app uses Google's Gemini multimodal AI to identify the item, extract the brand, categorize it, and estimate its secondhand market value, before saving it to a cloud database.

**Status:** Active Development (MVP)

## Tech Stack
* **Frontend:** Flutter & Dart
* **Backend:** Supabase (Postgres Database & Object Storage)
* **AI:** Google Gemini API (2.0 Flash)
* **Security:** flutter_dotenv (for API key protection)

## Features
* **AI Vision Analysis:** Automatically extracts brand, category, and price estimates from photos.
* **Human-in-the-Loop:** Populates an editable form for staff to verify AI suggestions before saving.
* **Live Inventory Grid:** A searchable, filterable grid view of the store's current stock.

## How to Run Locally

1. Clone the repository:
   ```bash
   git clone [https://github.com/YOUR_USERNAME/ai-thrift-manager.git](https://github.com/YOUR_USERNAME/ai-thrift-manager.git)
