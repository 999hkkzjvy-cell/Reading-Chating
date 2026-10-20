// Only allowlisted metadata is retained, in memory. Never retain URLs, bodies,
// headers, account identifiers, tokens, or raw exception messages.
const records = [];
const stages = {
  password: '密码登录',
  refresh: '会话刷新',
  user: '身份确认',
  profile: '个人资料',
  restore: '恢复登录状态',
};

function errorKind(error) {
  if (error?.code === 'invalid_credentials') return '凭据被拒绝';
  if (error?.code === 'email_not_confirmed') return '邮箱未验证';
  if (error?.name === 'AuthSessionMissingError') return '无可用会话';
  if (error?.status === 429) return '请求过于频繁';
  if (error?.status >= 500) return '服务异常';
  if (error?.name === 'AbortError' || error?.code === 'request_timeout') return '请求中止或超时';
  if (error?.name === 'AuthRetryableFetchError') return '网络请求异常';
  if (error?.name === 'TypeError') return '网络或程序异常';
  return '未分类异常';
}

export function beginAuthDiagnostic(stage, layer = '流程') {
  const record = {
    time: new Date().toISOString(),
    stage: stages[stage] || '认证',
    layer: layer === 'HTTP' ? 'HTTP' : '流程',
    result: '等待中',
    started: Date.now(),
  };
  records.push(record);
  if (records.length > 24) records.shift();
  return (error, status) => {
    record.elapsed = Date.now() - record.started;
    record.result = error ? errorKind(error) : '完成';
    if (Number.isInteger(status) && status >= 100 && status <= 599) record.status = status;
  };
}

export async function authStep(stage, operation) {
  const finish = beginAuthDiagnostic(stage);
  try {
    const result = await operation();
    if (result?.error) throw result.error;
    finish();
    return result;
  } catch (error) {
    finish(error, error?.status);
    throw error;
  }
}

export function createDiagnosticFetch(origin, fetchImpl = (...args) => fetch(...args)) {
  return async (input, init) => {
    let stage;
    try {
      const url = new URL(typeof input === 'string' || input instanceof URL ? input : input.url);
      if (url.origin === origin) {
        if (url.pathname === '/auth/v1/token') {
          const grant = url.searchParams.get('grant_type');
          stage = grant === 'password' ? 'password' : grant === 'refresh_token' ? 'refresh' : null;
        } else if (url.pathname === '/auth/v1/user') stage = 'user';
        else if (url.pathname === '/rest/v1/profiles') stage = 'profile';
      }
    } catch { /* Diagnostics must not change request behavior. */ }
    if (!stage) return fetchImpl(input, init);
    const finish = beginAuthDiagnostic(stage, 'HTTP');
    try {
      const response = await fetchImpl(input, init);
      finish(response.ok ? null : { status: response.status }, response.status);
      return response;
    } catch (error) {
      finish(error);
      throw error;
    }
  };
}

export function authDiagnosticReport() {
  const lines = records.map(record => {
    const time = new Date(record.time).toLocaleString('zh-CN', { timeZone: 'Asia/Shanghai', hour12: false });
    const elapsed = record.elapsed ?? (Date.now() - record.started);
    return `${time} | ${record.layer} ${record.stage} | ${record.result}${record.status ? ` HTTP ${record.status}` : ''} | ${elapsed}ms`;
  });
  return [
    '登录诊断 v1（北京时间，仅本页最近记录）',
    'HTTP 完成仅表示收到响应头；流程完成才表示该步骤处理结束。',
    '不包含邮箱、密码或令牌；不自动上传。',
    ...lines,
  ].join('\n');
}
