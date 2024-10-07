import pandas as pd
import numpy as np
from tqdm import tqdm
import concurrent.futures

def read_csv_file(csv_file):
    try:
        print(f"Reading CSV file: {csv_file}")
        df = pd.read_csv(csv_file)
        
        # 正确处理数据类型转换
        # 首先创建新的字符串类型列
        df['Source Port_str'] = df['Source Port'].apply(str)
        df['Destination Port_str'] = df['Destination Port'].apply(str)
        
        # 然后删除旧列并重命名新列
        df = df.drop(['Source Port', 'Destination Port'], axis=1)
        df = df.rename(columns={
            'Source Port_str': 'Source Port',
            'Destination Port_str': 'Destination Port'
        })
        
        return df
    except Exception as e:
        print(f"Error reading CSV file: {e}")
        return None

def read_excel_sheets(excel_file):
    try:
        print(f"Reading Excel file: {excel_file}")
        required_cols = ['Source Device', 'Source Port', 'Destination Device', 'Destination Port']
        
        excel = pd.ExcelFile(excel_file)
        all_sheets_data = []
        
        for sheet_name in tqdm(excel.sheet_names, desc="Reading Excel sheets"):
            try:
                sheet_data = pd.read_excel(excel_file, sheet_name=sheet_name, usecols=required_cols)
                
                # 正确处理Excel数据的类型转换
                sheet_data['Source Port'] = sheet_data['Source Port'].apply(str).str.split().str[0]
                sheet_data['Destination Port'] = sheet_data['Destination Port'].apply(str).str.split().str[0]
                
                sheet_data['Sheet Name'] = sheet_name
                all_sheets_data.append(sheet_data)
            except ValueError:
                continue
        
        if not all_sheets_data:
            return None
        
        combined_data = pd.concat(all_sheets_data, ignore_index=True)
        return combined_data
    except Exception as e:
        print(f"Error reading Excel file: {e}")
        return None


def process_chunk(chunk_data, excel_data):
    # 创建chunk的深复制以避免警告
    chunk = chunk_data.copy()
    
    # 在excel数据中查找匹配项
    merged = pd.merge(
        chunk,
        excel_data,
        on=['Source Device', 'Source Port'],
        how='left',
        suffixes=('_csv', '_excel')
    )
    
    # 处理完全匹配的情况
    matches_mask = (
        merged['Destination Device_excel'].notna() &
        (merged['Destination Device_csv'] == merged['Destination Device_excel']) &
        (merged['Destination Port_csv'] == merged['Destination Port_excel'])
    )
    matches = merged[matches_mask].copy()
    
    # 处理部分匹配但目标不同的情况
    diffs_mask = (
        merged['Destination Device_excel'].notna() &
        (~matches_mask)
    )
    diffs = merged[diffs_mask].copy()
    
    # 处理完全没有匹配的情况（unused）
    no_matches = merged[merged['Destination Device_excel'].isna()].copy()
    no_matches = no_matches[['Source Device', 'Source Port', 'Destination Device_csv', 'Destination Port_csv']].copy()
    no_matches.columns = ['Source Device', 'Source Port', 'Destination Device', 'Destination Port']
    
    return matches, diffs, no_matches


def compare_and_update_data(csv_data, excel_data):
    # 使用分块处理
    chunk_size = 10000
    csv_chunks = [csv_data.iloc[i:i+chunk_size].copy() for i in range(0, len(csv_data), chunk_size)]
    
    all_matches = []
    all_diffs = []
    all_no_matches = []
    
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
        future_to_chunk = {executor.submit(process_chunk, chunk, excel_data): chunk for chunk in csv_chunks}
        
        for future in tqdm(concurrent.futures.as_completed(future_to_chunk), total=len(csv_chunks), desc="Processing chunks"):
            matches, diffs, no_matches = future.result()
            all_matches.append(matches)
            all_diffs.append(diffs)
            all_no_matches.append(no_matches)
    
    # 合并结果
    matches_df = pd.concat(all_matches, ignore_index=True) if all_matches else pd.DataFrame()
    diffs_df = pd.concat(all_diffs, ignore_index=True) if all_diffs else pd.DataFrame()
    no_matches_df = pd.concat(all_no_matches, ignore_index=True) if all_no_matches else pd.DataFrame()
    
    return matches_df, diffs_df, no_matches_df


def save_results(match_df, diff_df, no_match_df):
    print("\nSaving results...")
    
    # 定义列顺序
    match_diff_columns = [
        'Source Device', 
        'Source Port', 
        'Destination Device_excel', 
        'Destination Port_excel',
        'Destination Device_csv', 
        'Destination Port_csv',  
        'Sheet Name'
    ]
    
    no_match_columns = [
        'Source Device',
        'Source Port',
        'Destination Device',
        'Destination Port'
    ]
    
    if not match_df.empty:
        # 重新排序列并保存
        ordered_match_df = match_df[match_diff_columns]
        ordered_match_df.to_excel('expected_results.xlsx', index=False)
        print(f"Saved {len(ordered_match_df)} matching connections to expected_results.xlsx")
    
    if not diff_df.empty:
        # 重新排序列并保存
        ordered_diff_df = diff_df[match_diff_columns]
        ordered_diff_df.to_excel('unexpected_results.xlsx', index=False)
        print(f"Saved {len(ordered_diff_df)} different connections to unexpected_results.xlsx")
    
    if not no_match_df.empty:
        # 重新排序列并保存
        ordered_no_match_df = no_match_df[no_match_columns]
        ordered_no_match_df.to_excel('unused.xlsx', index=False)
        print(f"Saved {len(ordered_no_match_df)} unmatched connections to unused.xlsx")

def main():
    csv_file = 'iblinkinfo_output_1250.csv'
    excel_file = 'topology_1250_servers-updated.xlsx'
    
    # 读取数据
    csv_data = read_csv_file(csv_file)
    if csv_data is None:
        return
    
    excel_data = read_excel_sheets(excel_file)
    if excel_data is None:
        return
    
    # 比较数据并生成结果
    match_df, diff_df, no_match_df = compare_and_update_data(csv_data, excel_data)
    
    # 保存结果
    save_results(match_df, diff_df, no_match_df)
    
    print("\nProcess completed successfully!")

if __name__ == "__main__":
    main()
