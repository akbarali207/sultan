const bcrypt = require('bcrypt')
const { Pool } = require('pg')
require('dotenv').config()

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
})

async function resetPassword() {
  const hash = await bcrypt.hash('123456', 10)
  const result = await pool.query(
    "UPDATE users SET password = $1 WHERE phone = '123456' RETURNING id, phone, role",
    [hash]
  )
  if (result.rows.length === 0) {
    console.log('No user found with phone 123456')
  } else {
    console.log('Password reset successfully:', result.rows[0])
  }
  await pool.end()
}

resetPassword().catch(console.error)
