"use strict";

// FastGPT _error.tsx 替代品 - 服务端 SSR 渲染
// 用途：消除原始 _error.tsx 内 useMount 的 toast + setTimeout 自动跳转副作用
// 镜像内路径：/app/projects/app/.next/server/pages/_error.js

const React = require("react");

const ErrorPage = function ErrorPage() {
  return React.createElement(
    "div",
    {
      style: {
        padding: "60px 40px",
        textAlign: "center",
        fontFamily: "system-ui, -apple-system, sans-serif",
        color: "#555"
      }
    },
    React.createElement(
      "h2",
      { style: { color: "#999", marginBottom: "16px" } },
      "Something went wrong"
    ),
    React.createElement(
      "p",
      { style: { fontSize: "14px" } },
      "Please use browser back button or navigate manually."
    )
  );
};

ErrorPage.getInitialProps = async function() {
  return { statusCode: 500 };
};

module.exports = { default: ErrorPage };
