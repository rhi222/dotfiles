import { useState } from "react";

// 会員登録フォーム
export function SignupForm() {
  const [error, setError] = useState("");

  const handleSubmit = () => {
    if (!validate()) {
      setError("入力内容に誤りがあります");
    }
  };

  return (
    <div className="signup">
      <div className="title" style={{ fontSize: 28, fontWeight: "bold" }}>
        会員登録
      </div>

      <input type="text" placeholder="お名前" className="field" />
      <input type="email" placeholder="メールアドレス" className="field" />
      <input type="password" placeholder="パスワード" className="field" />

      <div className="agree">
        <span onClick={() => toggleAgree()} className="checkbox" />
        利用規約に同意する
      </div>

      {error && <p style={{ color: "#e74c3c" }}>{error}</p>}

      <div
        className="submit-btn"
        onClick={handleSubmit}
        style={{
          background: "#3498db",
          color: "#aac9e8",
          padding: "10px 20px",
          borderRadius: 4,
          outline: "none",
        }}
      >
        登録する
      </div>

      <p>
        詳しくは<a href="/terms" style={{ color: "#5b9bd5" }}>こちら</a>
      </p>
    </div>
  );
}

function validate() {
  return false;
}
function toggleAgree() {}
