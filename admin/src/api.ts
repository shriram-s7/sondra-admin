import axios from "axios";

const api = axios.create({
  baseURL: import.meta.env.VITE_API_URL || "https://sondra-backend-cxkc.onrender.com",
});

// Request Interceptor: Attach JWT bearer token if available
api.interceptors.request.use(
  (config) => {
    const token = localStorage.getItem("sondra_token");
    if (token && config.headers) {
      config.headers.Authorization = `Bearer ${token}`;
    }
    return config;
  },
  (error) => {
    return Promise.reject(error);
  }
);

// Response Interceptor: Handle 401 Unauthorized globally
api.interceptors.response.use(
  (response) => response,
  (error) => {
    if (error.response && error.response.status === 401) {
      console.warn("Session expired. Logging out...");
      localStorage.removeItem("sondra_token");
      // Trigger redirect or page reload to prompt login
      window.location.reload();
    }
    return Promise.reject(error);
  }
);

export default api;
