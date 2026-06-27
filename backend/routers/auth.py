import os
from datetime import datetime, timedelta
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from jose import JWTError, jwt
from pydantic import BaseModel
import secrets
from dotenv import load_dotenv

# Load env variables
load_dotenv(override=True)

ADMIN_USERNAME = os.getenv("ADMIN_USERNAME", "admin")
ADMIN_PASSWORD = os.getenv("ADMIN_PASSWORD", "adminpassword")
JWT_SECRET = os.getenv("JWT_SECRET", "sondrasecretkey1234567890")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_DAYS = 30

router = APIRouter(prefix="/auth", tags=["Authentication"])

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/login")

class LoginRequest(BaseModel):
    username: str
    password: str

class Token(BaseModel):
    access_token: str
    token_type: str

def create_access_token(data: dict, expires_delta: Optional[timedelta] = None):
    to_encode = data.copy()
    if expires_delta:
        expire = datetime.utcnow() + expires_delta
    else:
        expire = datetime.utcnow() + timedelta(days=ACCESS_TOKEN_EXPIRE_DAYS)
    to_encode.update({"exp": expire})
    encoded_jwt = jwt.encode(to_encode, JWT_SECRET, algorithm=ALGORITHM)
    return encoded_jwt

@router.post("/login", response_model=Token)
def login(login_data: LoginRequest):
    # Use secrets.compare_digest to protect against timing attacks
    if not (
        secrets.compare_digest(login_data.username, ADMIN_USERNAME)
        and secrets.compare_digest(login_data.password, ADMIN_PASSWORD)
    ):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect username or password",
            headers={"WWW-Authenticate": "Bearer"},
        )
    
    access_token = create_access_token(data={"sub": login_data.username})
    return {"access_token": access_token, "token_type": "bearer"}

# Form data login endpoint (needed for OAuth2PasswordBearer standard docs/testing)
@router.post("/login/form", response_model=Token, include_in_schema=False)
def login_form(form_data: OAuth2PasswordRequestForm = Depends()):
    if not (
        secrets.compare_digest(form_data.username, ADMIN_USERNAME)
        and secrets.compare_digest(form_data.password, ADMIN_PASSWORD)
    ):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect username or password",
            headers={"WWW-Authenticate": "Bearer"},
        )
    
    access_token = create_access_token(data={"sub": form_data.username})
    return {"access_token": access_token, "token_type": "bearer"}

def get_current_admin(token: str = Depends(oauth2_scheme)):
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, JWT_SECRET, algorithms=[ALGORITHM])
        username: str = payload.get("sub")
        if username is None or username != ADMIN_USERNAME:
            raise credentials_exception
        return username
    except JWTError:
        raise credentials_exception

@router.get("/me")
def get_me(username: str = Depends(get_current_admin)):
    return {"username": username, "role": "admin"}

class PasswordChangeRequest(BaseModel):
    current_password: str
    new_password: str

@router.patch("/password")
def change_password(
    payload: PasswordChangeRequest,
    username: str = Depends(get_current_admin)
):
    global ADMIN_PASSWORD
    # Perform safe digest comparison
    if not secrets.compare_digest(payload.current_password, ADMIN_PASSWORD):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Incorrect current password"
        )
    
    ADMIN_PASSWORD = payload.new_password
    
    # Save the updated password to .env file for persistence
    try:
        possible_paths = [
            os.path.join(os.path.dirname(os.path.dirname(__file__)), ".env"),
            os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(__file__))), ".env"),
        ]
        env_path = None
        for p in possible_paths:
            if os.path.exists(p):
                env_path = p
                break
        if not env_path:
            env_path = possible_paths[0]
            
        if os.path.exists(env_path):
            with open(env_path, "r", encoding="utf-8") as f:
                lines = f.readlines()
                
            updated = False
            for idx, line in enumerate(lines):
                if line.strip().startswith("ADMIN_PASSWORD="):
                    lines[idx] = f"ADMIN_PASSWORD={payload.new_password}\n"
                    updated = True
                    break
            
            if not updated:
                lines.append(f"\nADMIN_PASSWORD={payload.new_password}\n")
                
            with open(env_path, "w", encoding="utf-8") as f:
                f.writelines(lines)
            print("Successfully updated password in .env file.")
    except Exception as e:
        print(f"Error persisting new password to .env file: {e}")
        
    return {"message": "Password changed successfully"}
